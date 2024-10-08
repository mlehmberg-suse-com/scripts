#!/bin/bash
cat rpms.txt | while read in; do
zypper search-packages --match-exact "$in" | grep "SUSEConnect --product" | grep -v "activate" >> repos.txt
done
