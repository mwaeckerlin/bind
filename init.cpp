/**

bind init: minimal, shell-free generator of the bind configuration and
entrypoint of the image. Same scratch / execv() pattern as the sibling
mwaeckerlin service containers.

  init --generate   the build: writes the configuration into /etc/bind from
                    the environment (domains.sh and the build arguments, see
                    generate-configuration.sh) and records the values it was
                    given in /usr/share/bind/defaults
  init [args]       the start: without a configuration variable in the
                    environment named runs on /etc/bind/named.conf, the built
                    or the mounted one; with one, the configuration is written
                    into /run/bind from the given values and the recorded
                    defaults, and named runs on that

Every value is checked before it is written, and the written configuration
passes named-checkconf before named starts. Further arguments go to named.

*/

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <exception>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace {

constexpr const char *NAMED        = "/usr/sbin/named";
constexpr const char *BUILT_DIR    = "/etc/bind";
constexpr const char *RUNTIME_DIR  = "/run/bind";
constexpr const char *DEFAULTS_DIR = "/usr/share/bind/defaults";
constexpr const char *PORT         = "9953";

const std::vector<std::string> VARIABLES = {
    "TTL", "SERIAL", "REFRESH", "RETRY", "EXPIRE", "NEGATIVE_CACHE_TTL",
    "SEVERITY", "TRANSFER", "RECURSION", "RATE_LIMIT", "MAILSERVER",
    "NAMESERVER", "HOSTMASTER", "IPV6", "DEFAULT_IP", "DEFAULT_SUBDOMAINS",
    "DEFAULT_DOMAINS", "DOMAINS"};

using Config = std::map<std::string, std::string>;

const std::string LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
const std::string DIGITS  = "0123456789";

std::string
env_or(const char *name, const std::string &fallback = {}) {
  const char *v = std::getenv(name);
  return (v && *v) ? std::string(v) : fallback;
}

bool
exists(const std::string &path) {
  struct stat st{};
  return stat(path.c_str(), &st) == 0;
}

std::string
read_file(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return {};
  return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

void
write_file(const std::string &path, const std::string &content) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) throw std::runtime_error("cannot write " + path + ": " + std::strerror(errno));
  out << content;
  out.close();
  if (!out) throw std::runtime_error("cannot write " + path);
}

void
make_directory(const std::string &path) {
  for (std::size_t pos = 1; pos <= path.size(); ++pos) {
    if (pos != path.size() && path[pos] != '/') continue;
    const std::string part = path.substr(0, pos);
    if (!exists(part) && ::mkdir(part.c_str(), 0755) != 0)
      throw std::runtime_error("cannot create " + part + ": " + std::strerror(errno));
  }
}

bool
all_of(const std::string &value, const std::string &allowed) {
  return !value.empty() && value.find_first_not_of(allowed) == std::string::npos;
}

// ${VALUE%;}
std::string
without_semicolon(const std::string &value) {
  return !value.empty() && value.back() == ';' ? value.substr(0, value.size() - 1) : value;
}

std::string
before(const std::string &value, char separator) {
  return value.substr(0, value.find(separator));
}

bool
contains(const std::string &value, char c) {
  return value.find(c) != std::string::npos;
}

std::string
after(const std::string &value, char separator) {
  return contains(value, separator) ? value.substr(value.find(separator) + 1) : std::string();
}

std::vector<std::string>
split_on(const std::string &value, const std::string &separators) {
  std::vector<std::string> result;
  std::string word;
  for (char c : value) {
    if (contains(separators, c)) {
      if (!word.empty()) result.push_back(word);
      word.clear();
    } else {
      word += c;
    }
  }
  if (!word.empty()) result.push_back(word);
  return result;
}

// split on `;` as the shell does with IFS=';': an empty field between two separators stays
std::vector<std::string>
fields(const std::string &value) {
  std::vector<std::string> result;
  std::size_t start = 0;
  while (start < value.size()) {
    const auto pos = value.find(';', start);
    if (pos == std::string::npos) {
      result.push_back(value.substr(start));
      break;
    }
    result.push_back(value.substr(start, pos - start));
    start = pos + 1;
  }
  return result;
}

// `echo -e`: DOMAINS is written with `\t` for a tabulator and `\n` for a line
std::string
unescape(const std::string &value) {
  std::string out;
  for (std::size_t i = 0; i < value.size(); ++i) {
    if (value[i] != '\\' || i + 1 == value.size()) {
      out += value[i];
      continue;
    }
    const char c = value[++i];
    switch (c) {
      case 'a': out += '\a'; break;
      case 'b': out += '\b'; break;
      case 'c': return out;
      case 'e': out += '\033'; break;
      case 'f': out += '\f'; break;
      case 'n': out += '\n'; break;
      case 'r': out += '\r'; break;
      case 't': out += '\t'; break;
      case 'v': out += '\v'; break;
      case '\\': out += '\\'; break;
      case '0': {
        int code = 0;
        for (int n = 0; n < 3 && i + 1 < value.size() && value[i + 1] >= '0' && value[i + 1] <= '7'; ++n)
          code = code * 8 + (value[++i] - '0');
        out += static_cast<char>(code);
        break;
      }
      default: out += '\\'; out += c;
    }
  }
  return out;
}

std::string
replace_all(std::string value, const std::string &from, const std::string &to) {
  for (std::size_t pos = 0; (pos = value.find(from, pos)) != std::string::npos; pos += to.size())
    value.replace(pos, from.size(), to);
  return value;
}

// ------------------------------------------------------------- validation ---

bool
valid_time(const std::string &v) {
  return all_of(v, DIGITS + "wdhmsWDHMS") && contains(DIGITS, v.front());
}

bool
valid_serial(const std::string &v) {
  return all_of(v, DIGITS) && v.size() <= 10;
}

bool
valid_number(const std::string &v) {
  return all_of(without_semicolon(v), DIGITS);
}

bool
valid_severity(const std::string &v) {
  for (const char *level : {"critical", "error", "warning", "notice", "info", "dynamic", "debug"})
    if (v == level) return true;
  return v.rfind("debug ", 0) == 0 && all_of(v.substr(6), DIGITS);
}

bool
valid_name(const std::string &v) {
  return all_of(v, LETTERS + DIGITS + ".-_");
}

bool
valid_address(const std::string &v) {
  return all_of(v, DIGITS + ".");
}

// an address match list stays inside its braces: no brace, quote or line break
bool
valid_match_list(const std::string &v) {
  return all_of(v, LETTERS + DIGITS + ".:/!; _-");
}

bool
valid_domain(const std::string &v) {
  return all_of(v, LETTERS + DIGITS + ".-") && v.front() != '.' && v.find("..") == std::string::npos;
}

void
check(const Config &config, const std::string &name, bool (*valid)(const std::string &), const char *expected) {
  const std::string &value = config.at(name);
  if (!value.empty() && !valid(value))
    throw std::runtime_error("ERROR: invalid " + name + ": '" + value + "', expected " + expected);
}

void
validate(const Config &config) {
  for (const char *name : {"TTL", "REFRESH", "RETRY", "EXPIRE", "NEGATIVE_CACHE_TTL"})
    check(config, name, valid_time, "seconds, or a time such as 1h30m");
  check(config, "SERIAL", valid_serial, "a number of at most ten digits");
  check(config, "RATE_LIMIT", valid_number, "a number of answers per second");
  check(config, "SEVERITY", valid_severity, "critical, error, warning, notice, info, debug or dynamic");
  for (const char *name : {"MAILSERVER", "NAMESERVER", "HOSTMASTER"})
    check(config, name, valid_name, "a host name");
  check(config, "DEFAULT_IP", valid_address, "an IPv4 address");
  for (const char *name : {"TRANSFER", "RECURSION", "IPV6"})
    check(config, name, valid_match_list, "addresses, networks or any and none, separated by semicolons");
}

// ------------------------------------------------------------- generation ---

struct Zone {
  std::string name, address, subdomains, records;
};

// one line of DOMAINS or DEFAULT_DOMAINS: name=address;subdomains;records
Zone
parse(const std::string &line, const std::string &default_ip) {
  Zone zone;
  zone.name = before(line, '=');
  if (!valid_domain(zone.name))
    throw std::runtime_error("ERROR: invalid domain name: '" + zone.name + "'");
  std::string args = contains(line, '=') ? after(line, '=') : default_ip;
  zone.address = before(args, ';');
  if (zone.address.empty()) zone.address = default_ip;
  args = after(args, ';');
  zone.subdomains = before(args, ';');
  zone.records = after(args, ';');
  return zone;
}

std::vector<Zone>
zones(const Config &config) {
  std::vector<std::string> lines;
  for (const auto &line : split_on(unescape(config.at("DOMAINS")), "\n")) {
    const auto start = line.find_first_not_of(" \t\r\v\f");
    if (start != std::string::npos) lines.push_back(line.substr(start));
  }
  for (const auto &name : split_on(config.at("DEFAULT_DOMAINS"), " \n"))
    lines.push_back(name);
  std::vector<Zone> result;
  for (const auto &line : lines) result.push_back(parse(line, config.at("DEFAULT_IP")));
  return result;
}

std::string
or_default(const std::string &value, const std::string &fallback) {
  return value.empty() ? fallback : value;
}

std::string
absolute_or(const std::string &value, const std::string &fallback) {
  return value.empty() ? fallback : value + ".";
}

std::string
named_conf(const Config &config, const std::string &dir) {
  const std::string recursion = config.at("RECURSION").empty()
      ? "  # authoritative-only server: never resolve foreign names for anyone\n"
        "  recursion no;"
      : "  # resolves foreign names for the clients named here\n"
        "  recursion yes;\n"
        "  allow-recursion { " + without_semicolon(config.at("RECURSION")) + "; };";
  const std::string ratelimit = config.at("RATE_LIMIT").empty() ? std::string() :
      "\n"
      "  # response rate limiting against reflection and amplification\n"
      "  rate-limit {\n"
      "    responses-per-second " + without_semicolon(config.at("RATE_LIMIT")) + ";\n"
      "    slip 2;\n"
      "    window 5;\n"
      "  };";
  const std::string ipv6 = without_semicolon(or_default(config.at("IPV6"), "none"));
  return
      "logging {\n"
      "  channel simplelog {\n"
      "    stderr;\n"
      "    severity " + or_default(config.at("SEVERITY"), "warning") + ";\n"
      "    print-category yes;\n"
      "    print-severity yes;\n"
      "    print-time yes;\n"
      "  };\n"
      "  category default { simplelog; };\n"
      "  category general { simplelog; };\n"
      "  category config { simplelog; };\n"
      "  category network { simplelog; };\n"
      "  category queries { simplelog; };\n"
      "  category security { simplelog; };\n"
      "};\n"
      "\n"
      "options {\n"
      "  directory \"/var/bind\";\n"
      "  pid-file \"/var/run/named/named.pid\";\n"
      "  listen-on port " + std::string(PORT) + " { any; };\n"
      + (ipv6 == "none" ? std::string("  listen-on-v6 { none; };\n")
                        : "  listen-on-v6 port " + std::string(PORT) + " { " + ipv6 + "; };\n")
      + recursion + "\n"
      "  # zone transfers are only allowed per zone when TRANSFER is set\n"
      "  allow-transfer { none; };\n"
      "  # do not disclose the bind version (version.bind CH TXT)\n"
      "  version none;" + ratelimit + "\n"
      "};\n"
      "\n"
      "# no remote control channel: named runs in foreground and is controlled by signals\n"
      "controls { };\n"
      "\n"
      "include \"" + dir + "/named.conf.local\";\n"
      "\n";
}

std::string
zone_file(const Config &config, const Zone &zone, const std::string &serial) {
  std::string out;
  out += "$TTL\t" + or_default(config.at("TTL"), "3600") + "\n";
  out += "@\tIN\tSOA\t" + zone.name + ". " + absolute_or(config.at("HOSTMASTER"), "root." + zone.name + ".") + " (\n";
  out += "\t\t\t" + serial + "\t; Serial\n";
  out += "\t\t\t" + or_default(config.at("REFRESH"), "3600") + "\t; Refresh\n";
  out += "\t\t\t" + or_default(config.at("RETRY"), "1800") + "\t; Retry\n";
  out += "\t\t\t" + or_default(config.at("EXPIRE"), "604800") + "\t; Expire\n";
  out += "\t\t\t" + or_default(config.at("NEGATIVE_CACHE_TTL"), "1800") + " )\t; Negative Cache TTL\n";
  out += ";\n";
  out += "@\tIN\tNS\t" + absolute_or(config.at("NAMESERVER"), "@") + "\n";
  out += "@\tIN\tA\t" + zone.address + "\n";
  out += "@\tIN\tMX 10\t" + absolute_or(config.at("MAILSERVER"), "@") + "\n";
  for (const auto &sub : split_on(or_default(zone.subdomains, or_default(config.at("DEFAULT_SUBDOMAINS"), "*")), " ")) {
    std::string address = after(sub, '=');
    const std::string type = contains(address, ':') ? before(address, ':') : std::string();
    if (contains(address, ':')) address = after(address, ':');
    out += before(sub, '=') + "\tIN\t" + or_default(type, "CNAME") + "\t" + or_default(address, "@") + "\n";
  }
  for (const auto &record : fields(zone.records))
    out += replace_all(record, "\\t", "\t") + "\n";
  return out;
}

std::string
zone_entry(const Config &config, const Zone &zone, const std::string &dir) {
  std::string out = "zone \"" + zone.name + "\" {\n\ttype master;\n\tallow-query { any; };\n";
  const std::string transfer = without_semicolon(config.at("TRANSFER"));
  if (!config.at("TRANSFER").empty())
    out += "\tnotify yes;\n\talso-notify { " + transfer + "; };\n\tallow-transfer { " + transfer + "; };\n";
  out += "\tfile \"" + dir + "/" + zone.name + "\";\n};\n";
  return out;
}

const char *
checkconf() {
  return exists("/usr/bin/named-checkconf") ? "/usr/bin/named-checkconf" : "/usr/sbin/named-checkconf";
}

void
check_configuration(const std::string &conf) {
  const pid_t pid = fork();
  if (pid < 0) throw std::runtime_error(std::string("cannot start named-checkconf: ") + std::strerror(errno));
  if (pid == 0) {
    const char *argv[] = {"named-checkconf", "-z", conf.c_str(), nullptr};
    execv(checkconf(), const_cast<char *const *>(argv));
    std::perror(checkconf());
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
    throw std::runtime_error("ERROR: the configuration in " + conf + " does not pass named-checkconf");
}

void
write_configuration(const Config &config, const std::string &dir) {
  validate(config);
  const auto list = zones(config);
  const std::string serial = or_default(config.at("SERIAL"), std::to_string(std::time(nullptr)));
  make_directory(dir);
  write_file(dir + "/named.conf", named_conf(config, dir));
  std::string local;
  for (const auto &zone : list) {
    std::cout << "... domain: " << zone.name << " -> " << zone.address << std::endl;
    write_file(dir + "/" + zone.name, zone_file(config, zone, serial));
    local += zone_entry(config, zone, dir);
  }
  if (local.empty()) ::unlink((dir + "/named.conf.local").c_str());
  else write_file(dir + "/named.conf.local", local);
  // the control channel is disabled, so the rndc key the package generates must not end up in the image
  ::unlink((dir + "/rndc.key").c_str());
  check_configuration(dir + "/named.conf");
}

void
record_defaults(const Config &config) {
  make_directory(DEFAULTS_DIR);
  for (const auto &[name, value] : config) {
    const std::string path = std::string(DEFAULTS_DIR) + "/" + name;
    if (value.empty()) ::unlink(path.c_str());
    else write_file(path, value);
  }
}

} // namespace

int main(int argc, char *argv[]) try {
  const bool generate = argc > 1 && std::string(argv[1]) == "--generate";
  Config config;
  bool given = false;
  for (const auto &name : VARIABLES) {
    const std::string value = env_or(name.c_str());
    given = given || !value.empty();
    config[name] = generate || !value.empty() ? value : read_file(std::string(DEFAULTS_DIR) + "/" + name);
  }

  if (generate) {
    write_configuration(config, BUILT_DIR);
    record_defaults(config);
    return 0;
  }

  std::string conf = std::string(BUILT_DIR) + "/named.conf";
  if (given) {
    std::cerr << "**** Writing the configuration from the environment into " << RUNTIME_DIR << std::endl;
    write_configuration(config, RUNTIME_DIR);
    conf = std::string(RUNTIME_DIR) + "/named.conf";
  }

  std::vector<const char *> exec_argv = {"named", "-f", "-c", conf.c_str(), "-L", "/dev/stdout"};
  for (int i = 1; i < argc; ++i) exec_argv.push_back(argv[i]);
  exec_argv.push_back(nullptr);
  execv(NAMED, const_cast<char *const *>(exec_argv.data()));
  std::perror(NAMED);
  return 1;
} catch (const std::exception &e) {
  std::cerr << e.what() << std::endl;
  return 1;
} catch (...) {
  std::cerr << "UNKNOWN ERROR" << std::endl;
  return 1;
}
