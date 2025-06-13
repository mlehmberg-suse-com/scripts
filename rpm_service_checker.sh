#!/bin/bash

# Script: rpm_service_checker.sh
# Description: Parses a list of RPMs to find their systemd services and compares them
#              against currently running systemd services on the system.
#              Can optionally get RPMs from 'zypper list-updates' if no input file is provided.

# Function to display script usage
usage() {
    echo "Usage: $0 [rpm_list_file]"
    echo "  [rpm_list_file]: Optional path to a text file containing a list of RPM package names,"
    echo "                   one RPM package name per line."
    echo "                   If not provided, the script will use packages listed by 'zypper list-updates'."
    echo ""
    echo "Example:"
    echo "  echo -e \"httpd\nsshd\" > my_rpms.txt"
    echo "  $0 my_rpms.txt"
    echo "  $0 # To use 'zypper list-updates' for RPM source"
    exit 1
}

# --- Input Validation ---

RPM_LIST_SOURCE_TYPE="file" # Default source type
RPM_LIST_FILE=""
RPM_NAMES_TEMP=RPM_NAMES_TEMP # Initialize for cleanup
RUNNING_SERVICES_TEMP=running_services_tmp.txt
INSTALLED_RPM_SERVICES_TEMP=INSTALLED_RPM_SERVICES_TEMP.txt
INSTALLED_RPM_SERVICES_TEMP2=INSTALLED_RPM_SERVICES_TEMP2.txt


# Determine if an RPM list file was provided or if zypper should be used
if [ -z "$1" ]; then
    RPM_LIST_SOURCE_TYPE="zypper_updates"
    echo "No RPM list file provided. Script will use packages from 'zypper list-updates'."
    # Check if 'zypper' command is available when no file is provided
    if ! command -v zypper &> /dev/null; then
        echo "Error: 'zypper' command not found. Cannot proceed without an RPM list file or 'zypper'."
        exit 1
    fi
else
    RPM_LIST_FILE="$1"
    # Check if the provided RPM list file exists
    if [ ! -f "$RPM_LIST_FILE" ]; then
        echo "Error: RPM list file '$RPM_LIST_FILE' not found."
        usage
    fi
fi


# Check if 'rpm' command is available
if ! command -v rpm &> /dev/null; then
    echo "Error: 'rpm' command not found. Please ensure RPM package manager is installed."
    exit 1
fi

# Check if 'systemctl' command is available
if ! command -v systemctl &> /dev/null; then
    echo "Error: 'systemctl' command not found. Please ensure systemd is running."
    exit 1
fi

# --- Main Script Logic ---

echo "--- Parsing RPMs for Associated Systemd Services ---"

# Create a temporary file to store service names found in RPMs
# Using mktemp for secure temporary file creation
if [ $? -ne 0 ]; then
    echo "Error: Failed to create temporary file for RPM services."
    exit 1
fi

# Declare an associative array to store unique service names found in RPMs
declare -a ALL_RPM_SERVICES

# Determine RPM source and populate the list of RPM names to process
if [ "$RPM_LIST_SOURCE_TYPE" == "zypper_updates" ]; then
    echo "Getting RPM packages from 'zypper list-updates'..."
    # Create a temporary file for zypper output
   # RPM_NAMES_TEMP=$(mktemp)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create temporary file for zypper RPM names."
        rm -f "$INSTALLED_RPM_SERVICES_TEMP"
        exit 1
    fi

    # Use 'zypper --non-interactive lu' to get updates without user interaction.
    # 'tail -n +5' skips typical header lines.
    # 'awk '{print $3}' extracts the package name (3rd column).
    # This might require adjustment based on specific zypper output format.
    zypper --non-interactive lu 2>/dev/null | tail -n +5 | awk '{print $7}' > "$RPM_NAMES_TEMP"
    RPM_SOURCE="$RPM_NAMES_TEMP"
    echo "Found $(wc -l < "$RPM_SOURCE") packages with updates."
else
    echo "Reading RPM packages from: $RPM_LIST_FILE"
    RPM_SOURCE="$RPM_LIST_FILE"
fi

# Loop through each RPM package name from the determined source
while IFS= read -r rpm_name; do
    # Skip empty lines
    if [ -z "$rpm_name" ]; then
        continue
    fi

    echo "Processing RPM: $rpm_name"

    # Use 'rpm -ql' to list all files installed by the RPM.
    # Filter for common systemd unit file extensions (.service, .target, .timer, .mount, .socket)
    # And filter for typical systemd unit directory paths.
    # Redirect stderr to /dev/null to suppress "package <name> is not installed" errors.
    rpm -ql "$rpm_name" 2>/dev/null | \
    grep -E '\.(service)$' | \
    grep -E '(/usr/lib/systemd/system/|/etc/systemd/system/|/run/systemd/system/|/usr/local/lib/systemd/system/)' | \
    while IFS= read -r unit_file_path; do
        # Extract just the filename (service name) from the full path
        service_name=$(basename "$unit_file_path")
        echo "  Found potential systemd unit: $service_name"
        # Add the service name to the associative array to ensure uniqueness
	ALL_RPM_SERVICES+=("$service_name")
	#echo Array contains " ${ALL_RPM_SERVICES[@]}" 
	#ALL_RPM_SERVICES["$service_name"]=1
       #for service in "${!ALL_RPM_SERVICES[@]}"; do
	#    echo "$service" >> $INSTALLED_RPM_SERVICES_TEMP
	#done
	echo " ${ALL_RPM_SERVICES[@]}" >> $INSTALLED_RPM_SERVICES_TEMP

    done
     # Cleanup file 
     sed -i '/^$/d' $INSTALLED_RPM_SERVICES_TEMP
     sed -i 's/ /\n/g' $INSTALLED_RPM_SERVICES_TEMP
     sort $INSTALLED_RPM_SERVICES_TEMP | uniq > INSTALLED_RPM_SERVICES_TEMP2.txt
     cp INSTALLED_RPM_SERVICES_TEMP2.txt $INSTALLED_RPM_SERVICES_TEMP
        


    # If the RPM was not found or had no service files, indicate it.
    if ! rpm -q "$rpm_name" &>/dev/null; then
        echo "  Warning: RPM '$rpm_name' does not appear to be installed or found."
    fi

done < "$RPM_SOURCE"

# Write the unique service names from the associative array to the temporary file
#for service in "${!ALL_RPM_SERVICES[@]}"; do
#   echo "$service" >> $INSTALLED_RPM_SERVICES_TEMP
#fone

# Sort the list of services for consistent output and for 'comm' command
sort -o $INSTALLED_RPM_SERVICES_TEMP $INSTALLED_RPM_SERVICES_TEMP

#echo -e "\n--- Listing Currently Running Systemd Services ---"

# Create a temporary file to store currently running service names
# RUNNING_SERVICES_TEMP=$(mktemp)
if [ $? -ne 0 ]; then
    echo "Error: Failed to create temporary file for running services."
    rm -f "$INSTALLED_RPM_SERVICES_TEMP"
    # Also clean up RPM_NAMES_TEMP if it was created
    [ -n "$RPM_NAMES_TEMP" ] && rm -f "$RPM_NAMES_TEMP"
    exit 1
fi

# Use 'systemctl list-units' to get all running service units.
# --type=service: only list services
# --state=running: only list running services
# --no-legend: suppress the header/footer
# --no-pager: prevent output from being piped to a pager
# awk '{print $1}': extract the first column, which is the unit name (e.g., httpd.service)
# sort: sort the list for 'comm' comparison
systemctl list-units --type=service --state=running --no-legend --no-pager | awk '{print $1}' | sort > "$RUNNING_SERVICES_TEMP"


echo -e "\n--- Comparison Results ---"

echo "1. Systemd Services found in the listed RPMs (from installed files):"
if [ -s "$INSTALLED_RPM_SERVICES_TEMP" ]; then # Check if file is not empty
    cat "$INSTALLED_RPM_SERVICES_TEMP"
else
    echo "  (No systemd services found for the listed RPMs or RPMs not installed.)"
fi

echo -e "\n2. Currently Running Systemd Services on this system:"
if [ -s "$RUNNING_SERVICES_TEMP" ]; then # Check if file is not empty
    cat "$RUNNING_SERVICES_TEMP"
else
    echo "  (No systemd services are currently running.)"
fi


echo -e "\n--- Detailed Comparison ---"
echo " (Note: 'comm' command requires sorted input files.)"
echo "  Column 1: Unique to RPMs"
echo "  Column 2: Unique to Running Services"
echo "  Column 3: Common to both"
comm -123 "$INSTALLED_RPM_SERVICES_TEMP" "$RUNNING_SERVICES_TEMP" # Display all 3 columns

echo -e "\n--- Services from RPMs that are currently RUNNING (Common to both) ---"
if [ -s "$INSTALLED_RPM_SERVICES_TEMP" ] && [ -s "$RUNNING_SERVICES_TEMP" ]; then
    comm -12 "$INSTALLED_RPM_SERVICES_TEMP" "$RUNNING_SERVICES_TEMP" || echo "  (None)"
else
    echo "  (Not applicable: one or both lists are empty.)"
fi

echo -e "\n--- Services from RPMs that are NOT currently RUNNING (Unique to RPMs) ---"
if [ -s "$INSTALLED_RPM_SERVICES_TEMP" ] && [ -s "$RUNNING_SERVICES_TEMP" ]; then
    comm -23 "$INSTALLED_RPM_SERVICES_TEMP" "$RUNNING_SERVICES_TEMP" || echo "  (All services from RPMs are running or no unique services.)"
elif [ -s "$INSTALLED_RPM_SERVICES_TEMP" ]; then
    cat "$INSTALLED_RPM_SERVICES_TEMP" # If no running services, all RPM services are "not running"
else
    echo "  (Not applicable: No systemd services found for the listed RPMs.)"
fi


echo -e "\n--- Running services NOT associated with listed RPMs (Unique to Running Services) ---"
if [ -s "$INSTALLED_RPM_SERVICES_TEMP" ] && [ -s "$RUNNING_SERVICES_TEMP" ]; then
    comm -13 "$INSTALLED_RPM_SERVICES_TEMP" "$RUNNING_SERVICES_TEMP" || echo "  (All running services are associated with the listed RPMs or no unique running services.)"
elif [ -s "$RUNNING_SERVICES_TEMP" ]; then
    cat "$RUNNING_SERVICES_TEMP" # If no RPM services, all running services are "not associated"
else
    echo "  (Not applicable: No systemd services are currently running.)"
fi

# --- Cleanup ---
rm -f "$INSTALLED_RPM_SERVICES_TEMP" "$INSTALLED_RPM_SERVICES_TEMP2"  "$RUNNING_SERVICES_TEMP"
[ -n "$RPM_NAMES_TEMP" ] && rm -f "$RPM_NAMES_TEMP" # Clean up zypper temp file
echo -e "\nScript finished. Temporary files cleaned up."

