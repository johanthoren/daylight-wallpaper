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
#folder="$HOME/some_folder"
#LAT="XX.XXXXXXX"
#LONG="XX.XXXXXXX"

usage() {
    cat <<EOF
Usage: $0 -h | [-d] -x LATITUDE -y LONGITUDE -f FOLDER"

       The FOLDER needs to contain the following images:"
       - night.jpg"
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

while getopts "dhx:y:f:" opt
   do
     case $opt in
        x) LAT=$OPTARG;;
        y) LONG=$OPTARG;;
        f) folder=$OPTARG;;
        d) debug=1;;
        h) usage 0;;
        *) usage 1;;

     esac
done

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
[ -z "$LAT" ] || [ -z "$LONG" ] || [ -z "$folder" ] && usage 1

# Set the boundraries of the current day.
DAY_BEGIN="$(date --date "$(date --iso)" +"%s")"
DAY_END="$(date --date "$(date --iso) 23:59:59" +"%s")"

print_debug() {
    [ "$debug" -eq 1 ] && echo "$1"
}

# Fetch the Sunrise and Sunset data from https://sunrise-sunset.org/api
fetch_sun_data() {
    print_debug "Performing new sun_data fetch."
    print_debug "Deleting old sun_data files"
    find /tmp -maxdepth 1 -name "sun_data*.json" -user "$USER" -delete

    print_debug "Fetching new sun_data from the API"
    sun_data="$(curl -s \
        https://api.sunrise-sunset.org/json\?lat="$LAT"\&lng="$LONG"\&formatted=0)"

    new_sun_data_file="/tmp/sun_data_"$(date +"%s")".json"
    print_debug "Saving sun data to file: $new_sun_data_file"
    echo "$sun_data" > "$new_sun_data_file"
}

# Check to see if there is already local sun_data saved from a previous run.
check_local_sun_data() {
    files="$(find /tmp -maxdepth 1 -name "sun_data*.json" -user "$USER")"
    number_of_files="$(wc -l <<< "$files")"

    print_debug "The following old sun_data files were found:"
    print_debug "$files"
    print_debug "Number of files: $number_of_files"

    if [ "$number_of_files" -eq 1 ]; then
        filename="${files[0]}"
        file_time_with_ending="${filename##*\_}"
        file_time="${file_time_with_ending%\.*}"
        print_debug "File time is $file_time"

        # If there already is a file that has been fetched the last day,
        # then use it to avoid using the API.
        if [ "$file_time" -ge "$DAY_BEGIN" ] && [ "$file_time" -lt "$DAY_END" ]; then
            print_debug "File time is within current day"
            sun_data="$(cat "$filename")"
        else
            print_debug "File time is NOT within current day"
            fetch_sun_data
        fi
    else
        print_debug "No files were found, or more than one file was found."
        fetch_sun_data
    fi
}

check_local_sun_data

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

# Exit if the fetch was not "OK".
API_STATUS="$(parse_response status)"
print_debug "API Status: $API_STATUS"

if [ "$API_STATUS" != "OK" ]; then
    echo "ERROR: The API request did not finish with an \"OK\" status"
    exit 1
fi

# Populate the vars to compare against. In chronological order.
NAUT_TWI_BEGIN="$(parse_response results nautical_twilight_begin)"
CIV_TWI_BEGIN="$(parse_response results civil_twilight_begin)"
SUNRISE="$(parse_response results sunrise)"
NOON="$(parse_response results solar_noon)"
SUNSET="$(parse_response results sunset)"
# I want to switch to another wallpaper when the afternoon is starting to head
# toward sunset.
LENGTH_OF_AFTERNOON=$((SUNSET-NOON))
LATE_AFTERNOON=$((NOON+LENGTH_OF_AFTERNOON/2))
CIV_TWI_END="$(parse_response results civil_twilight_end)"
NAUT_TWI_END="$(parse_response results nautical_twilight_end)"

# The local time as a unix timestamp.
TIME="$(date +"%s")"

if [ $debug -eq 1 ]; then
    cat <<EOF
The day begins at $DAY_BEGIN
The nautical twilight begins at $NAUT_TWI_BEGIN
The civil twilight begins at $CIV_TWI_BEGIN
The sunrise is at $SUNRISE
The noon is at $NOON
The late afternoon begins at $LATE_AFTERNOON
The sunset is at $SUNSET
The civil twilight ends at $CIV_TWI_END
The nautical twilight ends at $NAUT_TWI_END
The day ends at $DAY_END
The time is now $TIME
EOF
fi

[ "$TIME" -ge "$NAUT_TWI_END" ] || [ "$TIME" -lt "$NAUT_TWI_BEGIN" ] && period="night"
[ "$TIME" -ge "$NAUT_TWI_BEGIN" ] && [ "$TIME" -lt "$CIV_TWI_BEGIN" ] && period="nautical_dawn"
[ "$TIME" -ge "$CIV_TWI_BEGIN" ] && [ "$TIME" -lt "$SUNRISE" ] && period="civil_dawn"
[ "$TIME" -ge "$SUNRISE" ] && [ "$TIME" -lt "$NOON" ] && period="morning"
[ "$TIME" -ge "$NOON" ] && [ "$TIME" -lt "$LATE_AFTERNOON" ] && period="noon"
[ "$TIME" -ge "$LATE_AFTERNOON" ] && [ "$TIME" -lt "$SUNSET" ] && period="late_afternoon"
[ "$TIME" -ge "$SUNSET" ] && [ "$TIME" -lt "$CIV_TWI_END" ] && period="civil_dusk"
[ "$TIME" -ge "$CIV_TWI_END" ] && [ "$TIME" -lt "$NAUT_TWI_END" ] && period="nautical_dusk"
[ -z "$period" ] && echo "ERROR: Unable to determine period" && exit 1

# Remove any trailing slash before trying to use the folder.
trimmed_folder="${folder%/}"
WALLPAPER="${trimmed_folder}/${period}.jpg"

print_debug "It's currently: $period"
print_debug "Setting the wallpaper: $WALLPAPER"

feh --bg-fill "$WALLPAPER"
