#!/usr/bin/env python3
"""
Lightweight LDAP CLI Tool & HTTP Browser Service
Compatible with Python 3.9+ (Standard Library only)

Can be used as:
  1. A unified CLI tool for LDAP searches, listings, user/group management
  2. A lightweight HTTP web browser & curl endpoint for read-only LDAP browsing
"""

import argparse
import base64
import html
import json
import os
import re
import socketserver
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Dict, List, Optional, Tuple


# ── Configuration & Environment ──────────────────────────────────────────────

def load_env_file(filepath: str) -> Dict[str, str]:
    """Load key-value pairs from an env file if it exists."""
    env = {}
    if os.path.isfile(filepath):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        env[k.strip()] = v.strip().strip('"').strip("'")
        except Exception as e:
            sys.stderr.write(f"[WARN] Failed to read {filepath}: {e}\n")
    return env


def get_config() -> Dict[str, str]:
    """Resolve LDAP configuration from environment and fallback files."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    file_env = load_env_file(os.path.join(script_dir, "variables.env"))
    if not file_env:
        file_env = load_env_file("variables.env")

    ldap_url = os.environ.get("LDAP_URL") or file_env.get("LDAP_URL", "ldap://127.0.0.1:1389")
    ldap_basedn = os.environ.get("LDAP_BASEDN") or os.environ.get("LDAP_ROOT") or file_env.get("LDAP_BASEDN", "dc=sirius,dc=com")
    ldap_bind_dn = os.environ.get("LDAP_BIND_DN") or file_env.get("LDAP_BIND_DN", f"cn=admin,{ldap_basedn}")
    ldap_bind_pwd = os.environ.get("LDAP_BIND_PWD") or os.environ.get("LDAP_ADMIN_PASSWORD") or file_env.get("LDAP_BIND_PWD", "passw0rd")
    ldap_domain = os.environ.get("LDAP_DOMAIN") or file_env.get("LDAP_DOMAIN", "")

    if not ldap_domain and ldap_basedn:
        parts = [p.split("=")[1] for p in ldap_basedn.split(",") if p.lower().startswith("dc=")]
        ldap_domain = ".".join(parts) if parts else "sirius.com"

    http_port = int(os.environ.get("HTTP_PORT", "8080"))
    http_host = os.environ.get("HTTP_HOST", "0.0.0.0")

    return {
        "LDAP_URL": ldap_url,
        "LDAP_BASEDN": ldap_basedn,
        "LDAP_BIND_DN": ldap_bind_dn,
        "LDAP_BIND_PWD": ldap_bind_pwd,
        "LDAP_DOMAIN": ldap_domain,
        "HTTP_PORT": str(http_port),
        "HTTP_HOST": http_host,
    }


# ── LDIF Parsing & LDAP Execution ─────────────────────────────────────────────

def parse_ldif(ldif_text: str) -> List[Dict[str, List[str]]]:
    """Parse raw LDIF output into a list of entry dictionaries."""
    entries = []
    current_entry: Dict[str, List[str]] = {}

    # Unfold multiline LDIF lines (continuation lines start with space)
    unfolded_lines = []
    for line in ldif_text.splitlines():
        if line.startswith(" ") and unfolded_lines:
            unfolded_lines[-1] += line[1:]
        else:
            unfolded_lines.append(line)

    for line in unfolded_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            if current_entry:
                entries.append(current_entry)
                current_entry = {}
            continue

        if "::" in line:
            attr, b64val = line.split("::", 1)
            attr = attr.strip()
            try:
                decoded_val = base64.b64decode(b64val.strip()).decode("utf-8", errors="replace")
            except Exception:
                decoded_val = b64val.strip()
            current_entry.setdefault(attr, []).append(decoded_val)
        elif ":" in line:
            attr, val = line.split(":", 1)
            attr = attr.strip()
            current_entry.setdefault(attr, []).append(val.strip())

    if current_entry:
        entries.append(current_entry)

    return entries


def run_ldapsearch(filter_str: str, base_dn: Optional[str] = None, attributes: Optional[List[str]] = None, config: Optional[Dict[str, str]] = None) -> List[Dict[str, List[str]]]:
    """Run ldapsearch command and return parsed entries."""
    cfg = config or get_config()
    base = base_dn or cfg["LDAP_BASEDN"]
    
    cmd = [
        "ldapsearch",
        "-x",
        "-H", cfg["LDAP_URL"],
        "-D", cfg["LDAP_BIND_DN"],
        "-w", cfg["LDAP_BIND_PWD"],
        "-b", base,
        filter_str
    ]
    if attributes:
        cmd.extend(attributes)

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        if proc.returncode != 0:
            if "No such object" in proc.stderr:
                return []
            sys.stderr.write(f"[ERROR] ldapsearch failed (code {proc.returncode}): {proc.stderr}\n")
            return []
        return parse_ldif(proc.stdout)
    except FileNotFoundError:
        sys.stderr.write("[ERROR] 'ldapsearch' command not found. Please install openldap-clients.\n")
        return []


def run_ldapadd(ldif_content: str, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Run ldapadd with LDIF content passed via stdin."""
    cfg = config or get_config()
    cmd = [
        "ldapadd",
        "-x",
        "-H", cfg["LDAP_URL"],
        "-D", cfg["LDAP_BIND_DN"],
        "-w", cfg["LDAP_BIND_PWD"]
    ]
    try:
        proc = subprocess.run(cmd, input=ldif_content, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        if proc.returncode == 0:
            return True, proc.stdout.strip() or "Successfully added entry."
        return False, proc.stderr.strip()
    except FileNotFoundError:
        return False, "'ldapadd' command not found. Please install openldap-clients."


def run_ldapmodify(ldif_content: str, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Run ldapmodify with LDIF content passed via stdin."""
    cfg = config or get_config()
    cmd = [
        "ldapmodify",
        "-x",
        "-H", cfg["LDAP_URL"],
        "-D", cfg["LDAP_BIND_DN"],
        "-w", cfg["LDAP_BIND_PWD"]
    ]
    try:
        proc = subprocess.run(cmd, input=ldif_content, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        if proc.returncode == 0:
            return True, proc.stdout.strip() or "Successfully modified entry."
        return False, proc.stderr.strip()
    except FileNotFoundError:
        return False, "'ldapmodify' command not found. Please install openldap-clients."


def run_ldapdelete(dn: str, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Run ldapdelete for a given DN."""
    cfg = config or get_config()
    cmd = [
        "ldapdelete",
        "-x",
        "-H", cfg["LDAP_URL"],
        "-D", cfg["LDAP_BIND_DN"],
        "-w", cfg["LDAP_BIND_PWD"],
        dn
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        if proc.returncode == 0:
            return True, f"Successfully deleted DN: {dn}"
        return False, proc.stderr.strip()
    except FileNotFoundError:
        return False, "'ldapdelete' command not found. Please install openldap-clients."


# ── Domain LDAP Queries & Actions ─────────────────────────────────────────────

def get_first(entry: Dict[str, List[str]], attr: str, default: str = "") -> str:
    """Get the first value for an attribute from an entry."""
    vals = entry.get(attr, [])
    return vals[0] if vals else default


def get_groups_for_all_users(config: Optional[Dict[str, str]] = None) -> Dict[str, List[str]]:
    """Build a mapping of user DNs and UIDs to list of group names."""
    groups = list_groups(config=config)
    user_groups: Dict[str, List[str]] = {}
    for g in groups:
        group_cn = g.get("cn", "")
        if not group_cn:
            continue
        for member_dn in g.get("raw_members", []):
            clean_dn = member_dn.strip().lower()
            if group_cn not in user_groups.setdefault(clean_dn, []):
                user_groups[clean_dn].append(group_cn)
            match = re.search(r"uid=([^,]+)", member_dn, re.IGNORECASE)
            if match:
                u = match.group(1).strip().lower()
                if group_cn not in user_groups.setdefault(u, []):
                    user_groups[u].append(group_cn)
        for u in g.get("members", []):
            clean_u = u.strip().lower()
            if group_cn not in user_groups.setdefault(clean_u, []):
                user_groups[clean_u].append(group_cn)
    return user_groups


def get_user_groups(user_dn: str, user_uid: str, config: Optional[Dict[str, str]] = None) -> List[str]:
    """Find all group names (cn) that a user belongs to by querying groupOfUniqueNames."""
    cfg = config or get_config()
    clean_uid = user_uid.strip().lower()
    dn = user_dn.strip().lower() if user_dn else f"uid={clean_uid},ou=users,{cfg['LDAP_BASEDN'].lower()}"
    
    group_map = get_groups_for_all_users(config=cfg)
    groups = set()
    for g in group_map.get(dn, []):
        groups.add(g)
    for g in group_map.get(clean_uid, []):
        groups.add(g)

    return sorted(list(groups))


def list_users(config: Optional[Dict[str, str]] = None) -> List[Dict[str, Any]]:
    """List all users matching objectClass=inetOrgPerson with their groups populated."""
    cfg = config or get_config()
    entries = run_ldapsearch("(objectClass=inetOrgPerson)", attributes=["*", "+"], config=cfg)
    group_map = get_groups_for_all_users(config=cfg)

    users = []
    for e in entries:
        if "dn" not in e:
            continue
        dn = get_first(e, "dn")
        uid = get_first(e, "uid")
        
        # Combine operational memberOf with groupOfUniqueNames mapping
        groups_set = set()
        for mo in e.get("memberOf", []):
            match = re.search(r"cn=([^,]+)", mo, re.IGNORECASE)
            groups_set.add(match.group(1) if match else mo)
            
        for g_name in group_map.get(dn.lower(), []):
            groups_set.add(g_name)
        for g_name in group_map.get(uid.lower(), []):
            groups_set.add(g_name)

        users.append({
            "dn": dn,
            "uid": uid,
            "cn": get_first(e, "cn"),
            "givenName": get_first(e, "givenName"),
            "sn": get_first(e, "sn"),
            "mail": get_first(e, "mail"),
            "memberOf": sorted(list(groups_set)),
        })
    users.sort(key=lambda u: u.get("uid", ""))
    return users


def list_groups(config: Optional[Dict[str, str]] = None) -> List[Dict[str, Any]]:
    """List all groups matching objectClass=groupOfUniqueNames."""
    entries = run_ldapsearch("(objectClass=groupOfUniqueNames)", config=config)
    groups = []
    for e in entries:
        if "dn" not in e:
            continue
        members = e.get("uniqueMember", [])
        # Extract friendly UID or DN
        clean_members = []
        for m in members:
            match = re.search(r"uid=([^,]+)", m)
            clean_members.append(match.group(1) if match else m)

        groups.append({
            "dn": get_first(e, "dn"),
            "cn": get_first(e, "cn"),
            "description": get_first(e, "description"),
            "members": clean_members,
            "raw_members": members,
            "member_count": len(clean_members),
        })
    groups.sort(key=lambda g: g.get("cn", ""))
    return groups


def search_directory(query: str, config: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """Search users and groups matching query string."""
    cfg = config or get_config()
    q_esc = re.sub(r"([*()\\/\x00])", r"\\\1", query)
    user_filter = f"(&(objectClass=inetOrgPerson)(|(uid=*{q_esc}*)(cn=*{q_esc}*)(givenName=*{q_esc}*)(sn=*{q_esc}*)(mail=*{q_esc}*)))"
    group_filter = f"(&(objectClass=groupOfUniqueNames)(|(cn=*{q_esc}*)(description=*{q_esc}*)))"

    user_entries = run_ldapsearch(user_filter, attributes=["*", "+"], config=cfg)
    group_entries = run_ldapsearch(group_filter, config=cfg)
    group_map = get_groups_for_all_users(config=cfg)

    users = []
    for e in user_entries:
        if "dn" in e:
            dn = get_first(e, "dn")
            uid = get_first(e, "uid")
            groups_set = set()
            for mo in e.get("memberOf", []):
                match = re.search(r"cn=([^,]+)", mo, re.IGNORECASE)
                groups_set.add(match.group(1) if match else mo)
            for g_name in group_map.get(dn.lower(), []):
                groups_set.add(g_name)
            for g_name in group_map.get(uid.lower(), []):
                groups_set.add(g_name)

            users.append({
                "dn": dn,
                "uid": uid,
                "cn": get_first(e, "cn"),
                "givenName": get_first(e, "givenName"),
                "sn": get_first(e, "sn"),
                "mail": get_first(e, "mail"),
                "memberOf": sorted(list(groups_set)),
            })

    groups = []
    for e in group_entries:
        if "dn" in e:
            members = e.get("uniqueMember", [])
            clean_members = [re.search(r"uid=([^,]+)", m).group(1) if re.search(r"uid=([^,]+)", m) else m for m in members]
            groups.append({
                "dn": get_first(e, "dn"),
                "cn": get_first(e, "cn"),
                "description": get_first(e, "description"),
                "members": clean_members,
                "raw_members": members,
                "member_count": len(clean_members),
            })

    return {"query": query, "users": users, "groups": groups}


def get_user_by_uid(uid: str, config: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """Retrieve details for a single user by uid."""
    cfg = config or get_config()
    entries = run_ldapsearch(f"(&(objectClass=inetOrgPerson)(uid={uid}))", attributes=["*", "+"], config=cfg)
    if not entries:
        return None
    e = entries[0]
    dn = get_first(e, "dn")
    user_uid = get_first(e, "uid") or uid

    # Resolve groups
    groups_set = set()
    for mo in e.get("memberOf", []):
        match = re.search(r"cn=([^,]+)", mo, re.IGNORECASE)
        groups_set.add(match.group(1) if match else mo)
        
    for g_name in get_user_groups(dn, user_uid, config=cfg):
        groups_set.add(g_name)

    member_of_list = sorted(list(groups_set))

    # Add memberOf into all_attributes if not already present
    all_attrs = dict(e)
    if member_of_list and "memberOf" not in all_attrs:
        all_attrs["memberOf"] = [f"cn={g},ou=groups,{cfg['LDAP_BASEDN']}" for g in member_of_list]

    return {
        "dn": dn,
        "uid": user_uid,
        "cn": get_first(e, "cn"),
        "givenName": get_first(e, "givenName"),
        "sn": get_first(e, "sn"),
        "mail": get_first(e, "mail"),
        "memberOf": member_of_list,
        "all_attributes": all_attrs
    }


def get_group_by_name(cn: str, config: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    """Retrieve details for a single group by cn."""
    entries = run_ldapsearch(f"(&(objectClass=groupOfUniqueNames)(cn={cn}))", config=config)
    if not entries:
        return None
    e = entries[0]
    members = e.get("uniqueMember", [])
    clean_members = [re.search(r"uid=([^,]+)", m).group(1) if re.search(r"uid=([^,]+)", m) else m for m in members]
    return {
        "dn": get_first(e, "dn"),
        "cn": get_first(e, "cn"),
        "description": get_first(e, "description"),
        "members": clean_members,
        "raw_members": members,
        "member_count": len(clean_members),
        "all_attributes": e
    }


def add_user_action(first_name: str, last_name: str, password: str, group: Optional[str] = None, uid: Optional[str] = None, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Create a new user and optionally add to a group."""
    cfg = config or get_config()
    first_clean = first_name.strip()
    last_clean = last_name.strip()
    
    if not uid:
        first_char = first_clean[0].lower() if first_clean else ""
        last_lower = last_clean.lower().replace(" ", "")
        uid = f"{first_char}{last_lower}"

    mail = f"{uid}@{cfg['LDAP_DOMAIN']}"
    dn = f"uid={uid},ou=users,{cfg['LDAP_BASEDN']}"
    cn = f"{first_clean} {last_clean}"

    ldif = f"""dn: {dn}
objectClass: inetOrgPerson
cn: {cn}
givenName: {first_clean}
sn: {last_clean}
uid: {uid}
mail: {mail}
userPassword: {password}
"""
    success, msg = run_ldapadd(ldif, config=cfg)
    if not success:
        return False, f"Failed to add user: {msg}"

    if group:
        g_success, g_msg = add_user_to_group_action(uid, group, config=cfg)
        if not g_success:
            return True, f"User {uid} created, but failed to add to group '{group}': {g_msg}"
        return True, f"User {uid} created and added to group '{group}'."

    return True, f"User {uid} ({dn}) created successfully."


def add_group_action(group_name: str, description: Optional[str] = None, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Create a new groupOfUniqueNames entry."""
    cfg = config or get_config()
    group_clean = group_name.strip()
    dn = f"cn={group_clean},ou=groups,{cfg['LDAP_BASEDN']}"
    desc_line = f"\ndescription: {description}" if description else ""

    ldif = f"""dn: {dn}
objectClass: groupOfUniqueNames
cn: {group_clean}{desc_line}
uniqueMember: cn=admin,{cfg['LDAP_BASEDN']}
"""
    success, msg = run_ldapadd(ldif, config=cfg)
    if not success:
        return False, f"Failed to add group: {msg}"
    return True, f"Group {group_clean} ({dn}) created successfully."


def add_user_to_group_action(uid: str, group_name: str, config: Optional[Dict[str, str]] = None) -> Tuple[bool, str]:
    """Add a user's DN to uniqueMember of a group."""
    cfg = config or get_config()
    user_dn = f"uid={uid.strip()},ou=users,{cfg['LDAP_BASEDN']}"
    group_dn = f"cn={group_name.strip()},ou=groups,{cfg['LDAP_BASEDN']}"

    ldif = f"""dn: {group_dn}
changetype: modify
add: uniqueMember
uniqueMember: {user_dn}
"""
    success, msg = run_ldapmodify(ldif, config=cfg)
    if not success:
        return False, f"Failed to add user to group: {msg}"
    return True, f"User {uid} added to group {group_name}."


# ── Plain-Text / Table Formatting (for curl & CLI) ───────────────────────────

def format_table(headers: List[str], rows: List[List[str]]) -> str:
    """Format headers and rows as a neat text table."""
    if not rows:
        return "No entries found.\n"

    col_widths = [len(h) for h in headers]
    for row in rows:
        for idx, val in enumerate(row):
            if idx < len(col_widths):
                col_widths[idx] = max(col_widths[idx], len(str(val)))

    header_line = " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers))
    separator_line = "-+-".join("-" * col_widths[i] for i in range(len(headers)))
    
    out_rows = []
    for row in rows:
        formatted_row = " | ".join(str(val).ljust(col_widths[i]) if i < len(col_widths) else str(val) for i, val in enumerate(row))
        out_rows.append(formatted_row)

    return f"{header_line}\n{separator_line}\n" + "\n".join(out_rows) + "\n"


def format_users_text(users: List[Dict[str, Any]]) -> str:
    """Format users list into plain text."""
    headers = ["UID", "NAME", "EMAIL", "GROUPS"]
    rows = []
    for u in users:
        member_of_names = []
        for mo in u.get("memberOf", []):
            match = re.search(r"cn=([^,]+)", mo)
            member_of_names.append(match.group(1) if match else mo)
        groups_str = ", ".join(member_of_names) if member_of_names else "-"
        rows.append([u.get("uid", "-"), u.get("cn", "-"), u.get("mail", "-"), groups_str])
    return format_table(headers, rows)


def format_groups_text(groups: List[Dict[str, Any]]) -> str:
    """Format groups list into plain text."""
    headers = ["GROUP", "MEMBERS COUNT", "MEMBERS"]
    rows = []
    for g in groups:
        members_str = ", ".join(g.get("members", [])) if g.get("members") else "-"
        rows.append([g.get("cn", "-"), str(g.get("member_count", 0)), members_str])
    return format_table(headers, rows)


def format_search_text(result: Dict[str, Any]) -> str:
    """Format search results into plain text."""
    query = result.get("query", "")
    users = result.get("users", [])
    groups = result.get("groups", [])

    lines = [f"=== Search results for '{query}' ===", ""]
    lines.append(f"-- Users ({len(users)}) --")
    lines.append(format_users_text(users))
    lines.append(f"-- Groups ({len(groups)}) --")
    lines.append(format_groups_text(groups))
    return "\n".join(lines)


def get_help_text(config: Optional[Dict[str, str]] = None) -> str:
    """Generate plain-text help and endpoint documentation for curl/terminal users."""
    cfg = config or get_config()
    port = cfg.get("HTTP_PORT", "8080")
    base_url = f"http://localhost:{port}"

    return f"""OpenLDAP HTTP Service - Available Endpoints & Usage:

  Endpoint                 Description
  ----------------------   -------------------------------------------------
  GET /                    Show this help guide (with curl) or web UI (browser)
  GET /help                Show this help guide
  GET /users               List all users in the directory
  GET /groups              List all groups and their members
  GET /search?q=<query>    Search users & groups by name, uid, email, group
  GET /user?uid=<uid>      Get user details and group memberships by UID
  GET /group?cn=<name>     Get group details and member list by group name
  GET /healthz             Health check status

CLI / curl examples:
  curl {base_url}/
  curl {base_url}/users
  curl {base_url}/groups
  curl "{base_url}/search?q=doyle"
  curl {base_url}/user?uid=kdoyle
  curl {base_url}/group?cn=admin

JSON output:
  Add '?format=json' or header 'Accept: application/json' to any endpoint:
  curl -s {base_url}/users?format=json
  curl -s {base_url}/groups?format=json
  curl -s "{base_url}/search?q=doyle&format=json"
"""


# ── HTML View Rendering (for Web Browser) ─────────────────────────────────────

def render_html_page(title: str, content: str, query: str = "", active_tab: str = "users") -> str:
    """Render a clean, modern, standalone HTML page."""
    cfg = get_config()
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)} - LDAP Browser</title>
  <style>
    :root {{
      --bg: #f8fafc;
      --surface: #ffffff;
      --border: #e2e8f0;
      --text: #0f172a;
      --text-muted: #64748b;
      --primary: #0284c7;
      --primary-hover: #0369a1;
      --accent: #38bdf8;
      --badge-bg: #e0f2fe;
      --badge-text: #0369a1;
      --code-bg: #f1f5f9;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 24px;
    }}
    .container {{
      max-width: 1080px;
      margin: 0 auto;
    }}
    header {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 20px 24px;
      margin-bottom: 24px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    }}
    .header-top {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 16px;
    }}
    h1 {{ font-size: 1.4rem; font-weight: 700; color: var(--text); display: flex; align-items: center; gap: 8px; }}
    .badge {{
      background: var(--badge-bg);
      color: var(--badge-text);
      font-size: 0.75rem;
      font-weight: 600;
      padding: 3px 8px;
      border-radius: 4px;
    }}
    .server-info {{
      font-size: 0.82rem;
      color: var(--text-muted);
      display: flex;
      gap: 16px;
      flex-wrap: wrap;
    }}
    .search-bar {{
      display: flex;
      gap: 8px;
      margin-top: 12px;
    }}
    .search-input {{
      flex: 1;
      padding: 10px 14px;
      border: 1px solid var(--border);
      border-radius: 6px;
      font-size: 0.95rem;
      outline: none;
    }}
    .search-input:focus {{ border-color: var(--primary); ring: 2px var(--accent); }}
    .btn {{
      padding: 10px 18px;
      background: var(--primary);
      color: #fff;
      border: none;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      font-size: 0.9rem;
    }}
    .btn:hover {{ background: var(--primary-hover); }}
    .btn-secondary {{
      background: var(--code-bg);
      color: var(--text);
      border: 1px solid var(--border);
    }}
    .btn-secondary:hover {{ background: #e2e8f0; }}
    .nav-tabs {{
      display: flex;
      gap: 8px;
      margin-bottom: 20px;
    }}
    .tab {{
      padding: 8px 16px;
      border-radius: 6px;
      text-decoration: none;
      font-size: 0.9rem;
      font-weight: 600;
      color: var(--text-muted);
      background: transparent;
    }}
    .tab.active {{
      background: var(--primary);
      color: #fff;
    }}
    .card {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 20px;
      margin-bottom: 24px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      text-align: left;
      font-size: 0.9rem;
    }}
    th {{
      background: #f8fafc;
      padding: 10px 14px;
      font-weight: 600;
      color: var(--text-muted);
      border-bottom: 2px solid var(--border);
    }}
    td {{
      padding: 12px 14px;
      border-bottom: 1px solid var(--border);
      vertical-align: middle;
    }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background: #f8fafc; }}
    .tag {{
      display: inline-block;
      background: #f1f5f9;
      color: #334155;
      padding: 2px 7px;
      border-radius: 4px;
      font-size: 0.78rem;
      margin: 2px;
      text-decoration: none;
    }}
    .tag:hover {{ background: #e2e8f0; }}
    .curl-hint {{
      background: #1e293b;
      color: #f8fafc;
      padding: 12px 16px;
      border-radius: 6px;
      font-family: monospace;
      font-size: 0.85rem;
      margin-top: 16px;
      overflow-x: auto;
    }}
    footer {{
      text-align: center;
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-top: 32px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="header-top">
        <h1>
          <span>📂 OpenLDAP Directory</span>
          <span class="badge">Read-Only</span>
        </h1>
        <div class="server-info">
          <span><strong>Base DN:</strong> <code>{html.escape(cfg['LDAP_BASEDN'])}</code></span>
          <span><strong>Host:</strong> <code>{html.escape(cfg['LDAP_URL'])}</code></span>
        </div>
      </div>
      <form class="search-bar" action="/search" method="GET">
        <input class="search-input" type="text" name="q" placeholder="Search by name, uid, email, group..." value="{html.escape(query)}" autofocus>
        <button class="btn" type="submit">Search</button>
        {f'<a href="/" class="btn btn-secondary">Clear</a>' if query else ''}
      </form>
    </header>

    <div class="nav-tabs">
      <a class="tab {'active' if active_tab == 'users' else ''}" href="/users">Users</a>
      <a class="tab {'active' if active_tab == 'groups' else ''}" href="/groups">Groups</a>
      <a class="tab {'active' if active_tab == 'help' else ''}" href="/help">Help &amp; API</a>
      {f'<a class="tab active" href="#">Search Results</a>' if active_tab == 'search' else ''}
    </div>

    {content}

    <div class="curl-hint">
      💡 <strong>CLI / curl tip:</strong> Query this endpoint in terminal: 
      <code>curl -s http://localhost:{cfg['HTTP_PORT']}{'/search?q=' + html.escape(query) if query else '/users'}</code>
    </div>

    <footer>
      OpenLDAP Container Browser &bull; Sirius Cybernetics Corporation
    </footer>
  </div>
</body>
</html>
"""


def render_users_html(users: List[Dict[str, Any]], query: str = "") -> str:
    """Render users table in HTML."""
    if not users:
        return '<div class="card"><p style="color:var(--text-muted)">No users found.</p></div>'

    rows_html = []
    for u in users:
        member_tags = []
        for mo in u.get("memberOf", []):
            match = re.search(r"cn=([^,]+)", mo)
            g_name = match.group(1) if match else mo
            member_tags.append(f'<a class="tag" href="/group?cn={urllib.parse.quote(g_name)}">{html.escape(g_name)}</a>')
        tags_str = "".join(member_tags) if member_tags else '<span style="color:var(--text-muted)">-</span>'

        rows_html.append(f"""
        <tr>
          <td><strong><a href="/user?uid={urllib.parse.quote(u.get('uid', ''))}" style="color:var(--primary);text-decoration:none;">{html.escape(u.get('uid', ''))}</a></strong></td>
          <td>{html.escape(u.get('cn', ''))}</td>
          <td><a href="mailto:{html.escape(u.get('mail', ''))}" style="color:inherit">{html.escape(u.get('mail', ''))}</a></td>
          <td>{tags_str}</td>
        </tr>
        """)

    table_content = f"""
    <div class="card">
      <h2 style="font-size:1.1rem;margin-bottom:12px;">Users ({len(users)})</h2>
      <table>
        <thead>
          <tr>
            <th>UID</th>
            <th>Name</th>
            <th>Email</th>
            <th>Member Of</th>
          </tr>
        </thead>
        <tbody>
          {''.join(rows_html)}
        </tbody>
      </table>
    </div>
    """
    return render_html_page("Users", table_content, query=query, active_tab="users" if not query else "search")


def render_groups_html(groups: List[Dict[str, Any]], query: str = "") -> str:
    """Render groups table in HTML."""
    if not groups:
        return '<div class="card"><p style="color:var(--text-muted)">No groups found.</p></div>'

    rows_html = []
    for g in groups:
        member_tags = []
        for m in g.get("members", []):
            member_tags.append(f'<a class="tag" href="/user?uid={urllib.parse.quote(m)}">{html.escape(m)}</a>')
        tags_str = "".join(member_tags) if member_tags else '<span style="color:var(--text-muted)">-</span>'

        rows_html.append(f"""
        <tr>
          <td><strong><a href="/group?cn={urllib.parse.quote(g.get('cn', ''))}" style="color:var(--primary);text-decoration:none;">{html.escape(g.get('cn', ''))}</a></strong></td>
          <td><span class="badge">{g.get('member_count', 0)} members</span></td>
          <td>{tags_str}</td>
        </tr>
        """)

    table_content = f"""
    <div class="card">
      <h2 style="font-size:1.1rem;margin-bottom:12px;">Groups ({len(groups)})</h2>
      <table>
        <thead>
          <tr>
            <th>Group Name</th>
            <th>Count</th>
            <th>Members</th>
          </tr>
        </thead>
        <tbody>
          {''.join(rows_html)}
        </tbody>
      </table>
    </div>
    """
    return render_html_page("Groups", table_content, query=query, active_tab="groups" if not query else "search")


def render_user_detail_html(user: Optional[Dict[str, Any]], uid: str) -> str:
    """Render single user details page."""
    if not user:
        content = f'<div class="card"><p style="color:var(--text-muted)">User with UID <code>{html.escape(uid)}</code> not found.</p><p style="margin-top:12px"><a href="/users" class="btn btn-secondary">&larr; Back to users</a></p></div>'
        return render_html_page(f"User {uid}", content)

    member_tags = []
    for mo in user.get("memberOf", []):
        match = re.search(r"cn=([^,]+)", mo)
        g_name = match.group(1) if match else mo
        member_tags.append(f'<a class="tag" href="/group?cn={urllib.parse.quote(g_name)}">{html.escape(g_name)}</a>')
    tags_str = "".join(member_tags) if member_tags else '<span style="color:var(--text-muted)">None</span>'

    raw_attrs = user.get("all_attributes", {})
    raw_rows = []
    for k, v in raw_attrs.items():
        val_str = ", ".join(v) if isinstance(v, list) else str(v)
        raw_rows.append(f"<tr><th>{html.escape(k)}</th><td><code>{html.escape(val_str)}</code></td></tr>")

    content = f"""
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
        <h2>User: {html.escape(user.get('cn', uid))}</h2>
        <a href="/users" class="btn btn-secondary">&larr; Back to users</a>
      </div>
      <p style="margin-bottom:16px;"><strong>Groups:</strong> {tags_str}</p>
      <table>
        <tbody>
          {''.join(raw_rows)}
        </tbody>
      </table>
    </div>
    """
    return render_html_page(f"User {uid}", content)


def render_group_detail_html(group: Optional[Dict[str, Any]], cn: str) -> str:
    """Render single group details page."""
    if not group:
        content = f'<div class="card"><p style="color:var(--text-muted)">Group <code>{html.escape(cn)}</code> not found.</p><p style="margin-top:12px"><a href="/groups" class="btn btn-secondary">&larr; Back to groups</a></p></div>'
        return render_html_page(f"Group {cn}", content)

    member_tags = []
    for m in group.get("members", []):
        member_tags.append(f'<a class="tag" href="/user?uid={urllib.parse.quote(m)}">{html.escape(m)}</a>')
    tags_str = "".join(member_tags) if member_tags else '<span style="color:var(--text-muted)">No members</span>'

    content = f"""
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
        <h2>Group: {html.escape(group.get('cn', cn))}</h2>
        <a href="/groups" class="btn btn-secondary">&larr; Back to groups</a>
      </div>
      <p style="margin-bottom:8px;"><strong>DN:</strong> <code>{html.escape(group.get('dn', ''))}</code></p>
      <p style="margin-bottom:16px;"><strong>Members ({group.get('member_count', 0)}):</strong> {tags_str}</p>
    </div>
    """
    return render_html_page(f"Group {cn}", content)


def render_help_html() -> str:
    """Render help and endpoint documentation in HTML."""
    cfg = get_config()
    port = cfg.get("HTTP_PORT", "8080")
    base_url = f"http://localhost:{port}"

    content = f"""
    <div class="card">
      <h2 style="font-size:1.1rem;margin-bottom:16px;">HTTP Service Endpoints &amp; Usage</h2>
      <table>
        <thead>
          <tr>
            <th>Endpoint</th>
            <th>Description</th>
            <th>Example Link</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>GET /users</code></td>
            <td>List all users in the directory</td>
            <td><a href="/users">/users</a></td>
          </tr>
          <tr>
            <td><code>GET /groups</code></td>
            <td>List all groups and their members</td>
            <td><a href="/groups">/groups</a></td>
          </tr>
          <tr>
            <td><code>GET /search?q=&lt;term&gt;</code></td>
            <td>Search across users and groups</td>
            <td><a href="/search?q=doyle">/search?q=doyle</a></td>
          </tr>
          <tr>
            <td><code>GET /user?uid=&lt;uid&gt;</code></td>
            <td>Get detailed user attributes and assigned groups</td>
            <td><a href="/user?uid=kdoyle">/user?uid=kdoyle</a></td>
          </tr>
          <tr>
            <td><code>GET /group?cn=&lt;name&gt;</code></td>
            <td>Get detailed group attributes and member list</td>
            <td><a href="/group?cn=admin">/group?cn=admin</a></td>
          </tr>
          <tr>
            <td><code>GET /healthz</code></td>
            <td>Health check status</td>
            <td><a href="/healthz">/healthz</a></td>
          </tr>
          <tr>
            <td><code>GET /help</code></td>
            <td>This help and reference guide</td>
            <td><a href="/help">/help</a></td>
          </tr>
        </tbody>
      </table>

      <h3 style="font-size:0.95rem;margin-top:24px;margin-bottom:8px;">Terminal &amp; curl Usage</h3>
      <p style="font-size:0.85rem;color:var(--text-muted);margin-bottom:12px;">
        When querying this service via <code>curl</code> or any command-line tool, plain text tables are returned automatically:
      </p>
      <div class="curl-hint" style="margin-top:0;">
# Show help<br>
curl {base_url}/<br><br>
# List users and groups<br>
curl {base_url}/users<br>
curl {base_url}/groups<br><br>
# Search and inspect<br>
curl "{base_url}/search?q=doyle"<br>
curl {base_url}/user?uid=kdoyle
      </div>

      <h3 style="font-size:0.95rem;margin-top:24px;margin-bottom:8px;">JSON API</h3>
      <p style="font-size:0.85rem;color:var(--text-muted);margin-bottom:12px;">
        Append <code>?format=json</code> or pass header <code>Accept: application/json</code> for programmatic consumption:
      </p>
      <div class="curl-hint" style="margin-top:0;">
curl -s {base_url}/users?format=json
      </div>
    </div>
    """
    return render_html_page("Help & Endpoints", content, active_tab="help")


# ── HTTP Server Request Handler ───────────────────────────────────────────────

class LDAPBrowserHTTPHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler providing HTML, plain text, and JSON responses."""

    def is_curl_or_text_client(self) -> bool:
        """Check if request comes from curl, wget or explicitly requests text."""
        ua = self.headers.get("User-Agent", "").lower()
        accept = self.headers.get("Accept", "").lower()
        if "curl" in ua or "wget" in ua or "httpie" in ua:
            return True
        if "text/plain" in accept and "text/html" not in accept:
            return True
        return False

    def is_json_requested(self, query_params: Dict[str, List[str]]) -> bool:
        """Check if client wants JSON output."""
        fmt = query_params.get("format", [""])[0].lower()
        if fmt == "json":
            return True
        accept = self.headers.get("Accept", "").lower()
        return "application/json" in accept and "text/html" not in accept

    def respond(self, content: str, content_type: str = "text/html; charset=utf-8", status_code: int = 200):
        """Send an HTTP response."""
        data = content.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        """Handle GET requests."""
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path.rstrip("/") or "/"
        query_params = urllib.parse.parse_qs(parsed_url.query)

        force_text = self.is_curl_or_text_client() or query_params.get("format", [""])[0].lower() in ("text", "txt", "raw")
        wants_json = self.is_json_requested(query_params)

        if path == "/healthz" or path == "/status":
            self.respond("OK\n" if force_text else json.dumps({"status": "OK"}), "text/plain" if force_text else "application/json")
            return

        # Route: /help
        if path == "/help":
            if wants_json:
                help_dict = {
                    "endpoints": [
                        {"path": "/", "description": "Help guide (curl) or web UI (browser)"},
                        {"path": "/help", "description": "Show help guide"},
                        {"path": "/users", "description": "List all users"},
                        {"path": "/groups", "description": "List all groups and members"},
                        {"path": "/search?q=<query>", "description": "Search directory"},
                        {"path": "/user?uid=<uid>", "description": "Get user details by UID"},
                        {"path": "/group?cn=<name>", "description": "Get group details by name"},
                        {"path": "/healthz", "description": "Health check status"}
                    ]
                }
                self.respond(json.dumps(help_dict, indent=2), "application/json")
            elif force_text:
                self.respond(get_help_text(), "text/plain; charset=utf-8")
            else:
                self.respond(render_help_html())
            return

        # Route: /
        if path == "/":
            if force_text:
                self.respond(get_help_text(), "text/plain; charset=utf-8")
                return
            users = list_users()
            if wants_json:
                self.respond(json.dumps(users, indent=2), "application/json")
            else:
                self.respond(render_users_html(users))
            return

        # Route: /users
        if path == "/users":
            users = list_users()
            if wants_json:
                self.respond(json.dumps(users, indent=2), "application/json")
            elif force_text:
                self.respond(format_users_text(users), "text/plain; charset=utf-8")
            else:
                self.respond(render_users_html(users))
            return

        # Routes: /groups
        if path == "/groups":
            groups = list_groups()
            if wants_json:
                self.respond(json.dumps(groups, indent=2), "application/json")
            elif force_text:
                self.respond(format_groups_text(groups), "text/plain; charset=utf-8")
            else:
                self.respond(render_groups_html(groups))
            return

        # Routes: /search
        if path == "/search":
            q = query_params.get("q", [""])[0]
            result = search_directory(q)
            if wants_json:
                self.respond(json.dumps(result, indent=2), "application/json")
            elif force_text:
                self.respond(format_search_text(result), "text/plain; charset=utf-8")
            else:
                users_html = render_users_html(result["users"], query=q)
                self.respond(users_html)
            return

        # Routes: /user
        if path == "/user":
            uid = query_params.get("uid", [""])[0]
            user = get_user_by_uid(uid)
            if wants_json:
                self.respond(json.dumps(user or {}, indent=2), "application/json", 200 if user else 404)
            elif force_text:
                if not user:
                    self.respond(f"User with UID '{uid}' not found.\n", "text/plain", 404)
                else:
                    self.respond(format_users_text([user]), "text/plain; charset=utf-8")
            else:
                self.respond(render_user_detail_html(user, uid), "text/html; charset=utf-8", 200 if user else 404)
            return

        # Routes: /group
        if path == "/group":
            cn = query_params.get("cn", [""])[0]
            group = get_group_by_name(cn)
            if wants_json:
                self.respond(json.dumps(group or {}, indent=2), "application/json", 200 if group else 404)
            elif force_text:
                if not group:
                    self.respond(f"Group '{cn}' not found.\n", "text/plain", 404)
                else:
                    self.respond(format_groups_text([group]), "text/plain; charset=utf-8")
            else:
                self.respond(render_group_detail_html(group, cn), "text/html; charset=utf-8", 200 if group else 404)
            return

        # 404 Not Found
        if force_text:
            self.respond("404 Not Found\n", "text/plain", 404)
        else:
            self.respond(render_html_page("404 Not Found", '<div class="card"><h2>404 Not Found</h2><p style="margin-top:8px"><a href="/" class="btn btn-secondary">Home</a></p></div>'), "text/html", 404)

    def log_message(self, format, *args):
        """Suppress standard access logs unless in debug mode."""
        if os.environ.get("LDAP_HTTP_DEBUG") == "true":
            super().log_message(format, *args)


class ThreadedHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True


def start_http_server(host: Optional[str] = None, port: Optional[int] = None):
    """Run the threaded HTTP server."""
    cfg = get_config()
    h = host or cfg["HTTP_HOST"]
    p = port or int(cfg["HTTP_PORT"])

    server = ThreadedHTTPServer((h, p), LDAPBrowserHTTPHandler)
    print(f"[*] LDAP Browser HTTP server running at http://{h}:{p}/")
    print(f"[*] Point your web browser to http://localhost:{p}/ or use 'curl http://localhost:{p}/'")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down HTTP server...")
        server.server_close()


# ── Unified CLI Interface ─────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Unified OpenLDAP CLI & Lightweight HTTP Browser Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s list-users
  %(prog)s list-groups
  %(prog)s search-user kdoyle
  %(prog)s search-group admin
  %(prog)s search "Olivia"
  %(prog)s add-user "Alice" "Smith" "secret123" --group "research"
  %(prog)s add-to-group "asmith" "admin"
  %(prog)s delete-dn "uid=asmith,ou=users,dc=sirius,dc=com"
  %(prog)s serve --port 8080
"""
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # list-users
    sub_lu = subparsers.add_parser("list-users", help="List all users")
    sub_lu.add_argument("--json", action="store_true", help="Output in JSON format")

    # list-groups
    sub_lg = subparsers.add_parser("list-groups", help="List all groups and their members")
    sub_lg.add_argument("--json", action="store_true", help="Output in JSON format")

    # search-user
    sub_su = subparsers.add_parser("search-user", help="Search users by UID, Name, or Email")
    sub_su.add_argument("term", help="Search term (UID, common name, last name)")
    sub_su.add_argument("--json", action="store_true", help="Output in JSON format")

    # search-group
    sub_sg = subparsers.add_parser("search-group", help="Search group by group name (CN)")
    sub_sg.add_argument("name", help="Group name")
    sub_sg.add_argument("--json", action="store_true", help="Output in JSON format")

    # search
    sub_s = subparsers.add_parser("search", help="Search across users and groups")
    sub_s.add_argument("query", help="Search query")
    sub_s.add_argument("--json", action="store_true", help="Output in JSON format")

    # add-user
    sub_au = subparsers.add_parser("add-user", help="Add a new user")
    sub_au.add_argument("first_name", help="User's first name")
    sub_au.add_argument("last_name", help="User's last name")
    sub_au.add_argument("password", help="User's password")
    sub_au.add_argument("--group", "-g", help="Optional group name to assign user to")
    sub_au.add_argument("--uid", "-u", help="Optional explicit UID (defaults to <first_char><last_name>)")

    # add-group
    sub_ag = subparsers.add_parser("add-group", help="Add a new group")
    sub_ag.add_argument("name", help="Group name (CN)")
    sub_ag.add_argument("--description", "-d", help="Optional group description")

    # add-to-group
    sub_atg = subparsers.add_parser("add-to-group", help="Add existing user to group")
    sub_atg.add_argument("uid", help="User UID")
    sub_atg.add_argument("group", help="Group name (CN)")

    # delete-dn
    sub_del = subparsers.add_parser("delete-dn", help="Delete an LDAP entry by DN")
    sub_del.add_argument("dn", help="Full Distinguished Name (DN)")

    # serve
    sub_srv = subparsers.add_parser("serve", help="Run the read-only HTTP Browser & curl server")
    sub_srv.add_argument("--port", "-p", type=int, default=8080, help="HTTP port (default: 8080)")
    sub_srv.add_argument("--host", default="0.0.0.0", help="HTTP host bind address (default: 0.0.0.0)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "list-users":
        users = list_users()
        if args.json:
            print(json.dumps(users, indent=2))
        else:
            print(format_users_text(users), end="")

    elif args.command == "list-groups":
        groups = list_groups()
        if args.json:
            print(json.dumps(groups, indent=2))
        else:
            print(format_groups_text(groups), end="")

    elif args.command == "search-user":
        # Search by specific UID first, then general user filter
        user = get_user_by_uid(args.term)
        if user:
            res_users = [user]
        else:
            res = search_directory(args.term)
            res_users = res["users"]

        if args.json:
            print(json.dumps(res_users, indent=2))
        else:
            print(format_users_text(res_users), end="")

    elif args.command == "search-group":
        group = get_group_by_name(args.name)
        if group:
            res_groups = [group]
        else:
            res = search_directory(args.name)
            res_groups = res["groups"]

        if args.json:
            print(json.dumps(res_groups, indent=2))
        else:
            print(format_groups_text(res_groups), end="")

    elif args.command == "search":
        result = search_directory(args.query)
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(format_search_text(result), end="")

    elif args.command == "add-user":
        success, msg = add_user_action(args.first_name, args.last_name, args.password, group=args.group, uid=args.uid)
        print(msg)
        if not success:
            sys.exit(1)

    elif args.command == "add-group":
        success, msg = add_group_action(args.name, description=args.description)
        print(msg)
        if not success:
            sys.exit(1)

    elif args.command == "add-to-group":
        success, msg = add_user_to_group_action(args.uid, args.group)
        print(msg)
        if not success:
            sys.exit(1)

    elif args.command == "delete-dn":
        success, msg = run_ldapdelete(args.dn)
        print(msg)
        if not success:
            sys.exit(1)

    elif args.command == "serve":
        start_http_server(host=args.host, port=args.port)


if __name__ == "__main__":
    main()
