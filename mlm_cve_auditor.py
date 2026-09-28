#!/usr/bin/env python3
"""
SUSE Multi-Linux Manager (MLM) CVE Patch Query Tool
Reads CVEs from 'cve.txt' (or prompts for a file), groups target channels per distribution,
deduplicates entries per distribution, and reports missing CVE patches with Issue & Release Dates.
"""

import getpass
import os
import re
import ssl
import sys
import xmlrpc.client

# Configuration
MLM_SERVER = "mcl-suma"
API_URL = f"https://{MLM_SERVER}/rpc/api"

# Distribution to Channel Mapping
DISTRO_CHANNELS = {
    "MLS 7 / RES 7": [
        "res-7-ltss-updates-x86_64",
    ],
    "MLS 8 / RES 8": [
        "res-8-updates-x86_64",
        "res-cb-8-updates-x86_64",
        "res-as-8-updates-x86_64",
    ],
    "MLS 9 / SLL 9": [
        "sll-as-9-updates-x86_64",
        "sll-9-updates-x86_64",
        "sll-cb-9-updates-x86_64",
    ],
}


def load_cves():
    """Checks for default 'cve.txt' first; if missing, prompts the user for a filename."""
    default_filename = "cve.txt"

    if os.path.exists(default_filename):
        filename = default_filename
        print(f"[+] Found default file '{default_filename}'. Reading CVEs...")
    else:
        print(f"[!] Default file '{default_filename}' not found.")
        filename = input("Enter the CVE list filename/path: ").strip()

        if not os.path.exists(filename):
            print(f"[-] Error: File '{filename}' not found.")
            sys.exit(1)

    try:
        with open(filename, "r") as f:
            content = f.read()

        # Extract all CVE IDs matching pattern (e.g. CVE-2026-48962 or CVE-2006-10002)
        cves = re.findall(r"CVE-\d{4}-\d{4,7}", content, re.IGNORECASE)

        # Uppercase and deduplicate while preserving original order
        unique_cves = list(dict.fromkeys([c.upper() for c in cves]))

        if not unique_cves:
            print(
                f"[-] Error: No valid CVEs found in '{filename}'. Check file"
                " format."
            )
            sys.exit(1)

        print(
            f"[+] Successfully loaded {len(unique_cves)} unique CVE(s) from"
            f" '{filename}'."
        )
        return unique_cves

    except Exception as e:
        print(f"[-] Error reading file: {e}")
        sys.exit(1)


def print_table(rows):
    """Prints a formatted ASCII table."""
    if not rows:
        print("No records found.")
        return

    headers = [
        "CVE",
        "Distribution",
        "Advisory",
        "Issue Date",
        "Release Date",
        "Channel(s)",
        "Status / Synopsis",
    ]

    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, val in enumerate(row):
            col_widths[i] = max(col_widths[i], len(str(val)))

    row_format = " | ".join([f"{{:<{w}}}" for w in col_widths])
    separator = "-+-".join(["-" * w for w in col_widths])

    print("\n" + row_format.format(*headers))
    print(separator)
    for row in rows:
        print(row_format.format(*row))


def main():
    # 1. Load CVEs
    cve_list = load_cves()

    # 2. Get MLM credentials
    username = input("MLM Username: ")
    password = getpass.getpass("MLM Password: ")

    # Bypass SSL Certificate validation (internal / self-signed CA certs)
    ssl_context = ssl._create_unverified_context()
    client = xmlrpc.client.ServerProxy(API_URL, context=ssl_context)

    try:
        session = client.auth.login(username, password)
        print(f"\n[+] Connected to MLM at {MLM_SERVER}")
    except Exception as e:
        print(f"[-] Authentication failed: {e}")
        sys.exit(1)

    table_rows = []
    missing_report = []

    print("[+] Querying MLM and analyzing distribution status...\n")

    for cve in cve_list:
        try:
            errata_list = client.errata.findByCve(session, cve)

            # Map of found channels -> errata info
            found_by_channel = {}

            if errata_list:
                for errata in errata_list:
                    advisory_name = errata.get(
                        "advisory_name", errata.get("advisory", "Unknown")
                    )

                    try:
                        channels = client.errata.applicableToChannels(
                            session, advisory_name
                        )
                    except Exception:
                        channels = []

                    synopsis = "N/A"
                    issue_date = errata.get(
                        "issue_date", errata.get("date", "N/A")
                    )
                    release_date = "N/A"

                    try:
                        details = client.errata.getDetails(
                            session, advisory_name
                        )
                        if details:
                            synopsis = (
                                details.get("synopsis")
                                or details.get("advisory_synopsis")
                                or details.get("summary")
                                or "N/A"
                            )
                            issue_date = (
                                details.get("issue_date")
                                or details.get("date")
                                or issue_date
                            )
                            # Extract release or update date
                            release_date = (
                                details.get("update_date")
                                or details.get("last_modified_date")
                                or details.get("updated")
                                or issue_date
                            )
                    except Exception:
                        synopsis = (
                            errata.get("synopsis")
                            or errata.get("summary")
                            or "N/A"
                        )
                        release_date = issue_date

                    for ch in channels:
                        label = ch.get("label")
                        if label not in found_by_channel:
                            found_by_channel[label] = []
                        found_by_channel[label].append((
                            advisory_name,
                            issue_date,
                            release_date,
                            synopsis,
                        ))

            # Evaluate coverage for each distribution with deduplication
            for distro_name, channel_list in DISTRO_CHANNELS.items():
                distro_found = False
                # Dictionary to deduplicate advisories per distribution
                deduped_advisories = {}

                for ch_label in channel_list:
                    if ch_label in found_by_channel:
                        distro_found = True
                        for (
                            adv_name,
                            i_date,
                            r_date,
                            syn,
                        ) in found_by_channel[ch_label]:
                            if adv_name not in deduped_advisories:
                                deduped_advisories[adv_name] = {
                                    "issue_date": i_date,
                                    "release_date": r_date,
                                    "synopsis": syn,
                                    "channels": [],
                                }
                            if (
                                ch_label
                                not in deduped_advisories[adv_name]["channels"]
                            ):
                                deduped_advisories[adv_name]["channels"].append(
                                    ch_label
                                )

                # Append deduplicated rows for this distribution
                if distro_found:
                    for adv_name, adv_info in deduped_advisories.items():
                        ch_str = ", ".join(adv_info["channels"])
                        table_rows.append([
                            cve,
                            distro_name,
                            adv_name,
                            adv_info["issue_date"],
                            adv_info["release_date"],
                            ch_str,
                            adv_info["synopsis"],
                        ])
                else:
                    table_rows.append([
                        cve,
                        distro_name,
                        "MISSING",
                        "N/A",
                        "N/A",
                        "N/A",
                        "Patch Missing for Distribution",
                    ])
                    missing_report.append((cve, distro_name))

        except Exception as err:
            table_rows.append(
                [cve, "ALL", "ERROR", "N/A", "N/A", "N/A", str(err)]
            )

    # Output Results Table
    print_table(table_rows)

    # Print Summary of Missing CVEs
    print("\n" + "=" * 75)
    print(" MISSING PATCH SUMMARY")
    print("=" * 75)
    if missing_report:
        for cve, distro in missing_report:
            print(f" [!] {cve} is MISSING from distribution: {distro}")
    else:
        print(" [+] All CVEs have matching patches in all target distributions!")

    client.auth.logout(session)
    print("\n[+] Query complete.")


if __name__ == "__main__":
    main()
