#!/usr/bin/bash
# Copyright 2020 Johan Thorén <johan@thoren.xyz>

# Licensed under the ISC license:

# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.

# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

# Optional, set these vars here instead of passing them as options.
#FOLDER="$HOME/some_folder"
#LAT="XX.XXXXXXX"
#LONG="XX.XXXXXXX"

usage() {
    cat <<EOF
Usage: $0 -h | [-d] -x LATITUDE -y LONGITUDE -f FOLDER

       The FOLDER needs to contain the following images:
       - default.jpg
       - night.jpg
       - nautical_dawn.jpg
       - civil_dawn.jpg
       - morning.jpg
       - noon.jpg
       - late_afternoon.jpg
       - civil_dusk.jpg
       - nautical_dusk.jpg
EOF
    exit "$1"
}

debug=0

print_debug() {
    [ "$debug" -eq 1 ] && echo "$1"
}

verify_requirements() {
    # Make sure that all required commands are available.
    if ! command -v curl > /dev/null 2>&1; then
        echo "ERROR: curl is not installed"
        exit 1
    elif ! command -v feh > /dev/null 2>&1; then
        echo "ERROR: feh is not installed"
        exit 1
    elif ! command -v jq > /dev/null 2>&1; then
        echo "ERROR: jq is not installed"
        exit 1
    fi

    # Make sure that all required variables are set.
    [ -z "$LAT" ] || [ -z "$LONG" ] || [ -z "$FOLDER" ] && usage 1
}

# Set the boundraries of the current day.
define_day() {
    day_begin="$(date --date "$(date --iso)" +"%s")"
    print_debug "The day begins at $day_begin"
    day_end="$(date --date "$(date --iso) 23:59:59" +"%s")"
    print_debug "The day ends at $day_end"
}

delete_old_files() {
    print_debug "Deleting old sun_data files"
    find /tmp -maxdepth 1 -name "sun_data*.json" -user "$USER" -delete
}

# Fetch the Sunrise and Sunset data from https://sunrise-sunset.org/api
fetch_sun_data() {
    delete_old_files
    print_debug "Fetching new sun_data from the API"
    sun_data="$(curl -s \
        https://api.sunrise-sunset.org/json\?lat="$LAT"\&lng="$LONG"\&formatted=0)"

    new_sun_data_file="/tmp/sun_data_$(date +"%s").json"
    print_debug "Saving sun data to file: $new_sun_data_file"
    echo "$sun_data" > "$new_sun_data_file"
}

find_sun_data_files() {
    find /tmp -maxdepth 1 -name "sun_data*.json" -user "$USER"
}

# Check to see if there is already local sun_data saved from a previous run.
check_local_sun_data() {
    files="$(find_sun_data_files)"
    number_of_files="$(find_sun_data_files | wc -l)"

    if [ "$number_of_files" -eq 1 ]; then
        print_debug "The following old sun_data files were found:"
        print_debug "$files"
        print_debug "Number of files: $number_of_files"
        local_file_name="${files[0]}"
        file_time_with_ending="${local_file_name##*\_}"
        file_time="${file_time_with_ending%\.*}"
        print_debug "The local sun_data file time is $file_time"

        # If there already is a file that has been fetched the last day,
        # then use it to avoid using the API.
        if [ "$file_time" -ge "$day_begin" ] && [ "$file_time" -lt "$day_end" ]
        then
            print_debug "File time is within current day"
            sun_data="$(cat "$local_file_name")"
        else
            print_debug "File time is NOT within current day"
            fetch_sun_data
        fi
    else
        print_debug "No files were found, or more than one file was found."
        fetch_sun_data
    fi
}

# Parse the json response to extract the wanted string.
parse_response() {
    if [ "$#" -eq 1 ]; then
        jq --arg x "$1" '.[$x]' <<< "$sun_data" | sed 's/\"//g'
    elif [ "$#" -eq 2 ]; then
        date_time="$(jq --arg x "$1" --arg y "$2" '.[$x][$y]' \
            <<< "$sun_data" | sed 's/\"//g')"
        # Transform to unix timestamp for easy math.
        date --date "$date_time" +"%s"
    else
        echo "ERROR: Illegal number of parameters to parse_response"
        exit 1
    fi
}

set_wallpaper() {
    # Remove any trailing slash before trying to use the folder.
    trimmed_folder="${FOLDER%/}"
    wallpaper="${trimmed_folder}/${period}.jpg"

    print_debug "Setting the wallpaper: $wallpaper"

    feh --bg-fill "$wallpaper"
}

# Error handling if the sun_data is not "OK".
validate_sun_data() {
    i=0
    while [ "$i" -le 2 ]; do
         print_debug "Validation try: $i"
         api_status="$(parse_response status)"
         print_debug "API Status: $api_status"

         if [ "$api_status" != "OK" ]; then
             print_debug "The API request did not finish with an \"OK\" status"
             print_debug "Trying again in 10 seconds"
             sleep 10
             fetch_sun_data
             ((++i))
             if [ "$i" -eq 2 ]; then
                 print_debug "Too many failed validation attempts"
                 print_debug "Falling back to default wallpaper"
                 delete_old_files
                 period="default"
                 set_wallpaper
                 exit 1
             fi
         else
             break
         fi
    done
}

# Populate the vars to compare against. In chronological order.
populate_vars() {
    naut_twi_begin="$(parse_response results nautical_twilight_begin)"
    civ_twi_begin="$(parse_response results civil_twilight_begin)"
    sunrise="$(parse_response results sunrise)"
    noon="$(parse_response results solar_noon)"
    sunset="$(parse_response results sunset)"
    # I want to switch to another wallpaper when the afternoon is starting to
    # head toward sunset.
    length_of_afternoon=$((sunset-noon))
    late_afternoon=$((noon+length_of_afternoon/2))
    civ_twi_end="$(parse_response results civil_twilight_end)"
    naut_twi_end="$(parse_response results nautical_twilight_end)"

    # The local time as a unix timestamp.
    time="$(date +"%s")"
}

determine_period() {
    [ "$time" -ge "$naut_twi_end" ] || [ "$time" -lt "$naut_twi_begin" ] && period="night" && return
    [ "$time" -ge "$naut_twi_begin" ] && [ "$time" -lt "$civ_twi_begin" ] && period="nautical_dawn" && return
    [ "$time" -ge "$civ_twi_begin" ] && [ "$time" -lt "$sunrise" ] && period="civil_dawn" && return
    [ "$time" -ge "$sunrise" ] && [ "$time" -lt "$noon" ] && period="morning" && return
    [ "$time" -ge "$noon" ] && [ "$time" -lt "$late_afternoon" ] && period="noon" && return
    [ "$time" -ge "$late_afternoon" ] && [ "$time" -lt "$sunset" ] && period="late_afternoon" && return
    [ "$time" -ge "$sunset" ] && [ "$time" -lt "$civ_twi_end" ] && period="civil_dusk" && return
    [ "$time" -ge "$civ_twi_end" ] && [ "$time" -lt "$naut_twi_end" ] && period="nautical_dusk" && return
    [ -z "$period" ] && echo "ERROR: Unable to determine period" && exit 1
}

debug_summary() {
    if [ $debug -eq 1 ]; then
        cat <<EOF
Nautical twilight begins at $naut_twi_begin
Civil twilight begins at $civ_twi_begin
Sunrise is at $sunrise
Noon is at $noon
Late afternoon begins at $late_afternoon
Sunset is at $sunset
Civil twilight ends at $civ_twi_end
Nautical twilight ends at $naut_twi_end
The time is now $time
It's currently: $period
EOF
    fi
}

while getopts "dhx:y:f:" opt
   do
     case $opt in
        x) LAT=$OPTARG;;
        y) LONG=$OPTARG;;
        f) FOLDER=$OPTARG;;
        d) debug=1;;
        h) usage 0;;
        *) usage 1;;
     esac
done

main() {
    verify_requirements
    define_day
    check_local_sun_data
    validate_sun_data
    populate_vars
    determine_period
    debug_summary
    set_wallpaper
}

main
