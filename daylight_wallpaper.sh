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
#lat=""
#lon=""
cmd="feh --bg-fill"
purge=0
verbose=0

die() {
  case "${-}" in
    (*i*) printf -- '\e[38;5;9mERROR: %s\e[m\n' "${0}:(${LINENO}): ${*}" >&2 ;;
    (*)   printf -- 'ERROR: %s\n' "${0}:(${LINENO}): ${*}" >&2 ;;
  esac
  exit 1
}

print_v() {
    [ "$verbose" -eq 1 ] && printf "$(timestamp) %s\n" "$1"
}

usage() {
    cat <<EOF
Usage: $0 -h | [-c COMMAND] [-p] [-v] [-x LATITUDE -y LONGITUDE] -f FOLDER

       -c Command to use to set the wallpaper instead of feh
          (assuming that the path to the wallpaper should follow the command)
       -f Folder containing the wallpapers
       -h Print this text
       -p Purge old files
       -v Verbose output
       -x Latitude  -- must be used together with -y
       -y Longitude -- must be used together with -x

       The FOLDER needs to contain the following images:
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

timestamp() {
    printf '%s' "[$(date +"%Y-%m-%d %T %Z")]"
}

to_time() {
    date --date "@${1}" +"%T"
}

# Delete old files in /tmp.
# Provide eith "geo" or "sun" as first argument to delete files of that type.
delete_old_files() {
    print_v "Deleting old ${1}_data files."
    find /tmp -maxdepth 1 -name "${1}_data*.json" -user "$USER" -delete
}

# Purge all old files.
purge_old_files() {
    if [ "$purge" -eq 1 ]; then
        print_v "Purging old files."
        delete_old_files "geo"
        delete_old_files "sun"
    fi
}

verify_requirements() {
    # Make sure that all required commands are available.
    command -v curl > /dev/null 2>&1 || die "curl is not installed."
    command -v jq > /dev/null 2>&1 || die "jq is not installed."

    if [[ $cmd == feh* ]]; then
        command -v feh > /dev/null 2>&1 || die "feh is not installed."
    fi

    # Make sure that all required constants are set.
    [ -z "$FOLDER" ] && usage 1

    # If you use options x or y, you have to use both.
    { [ -n "$lat" ] && [ -z "$lon" ]; } || { [ -z "$lat" ] && [ -n "$lon" ]; } \
        && die "When using options -x or -y, both options must be used."
}

# Set the boundraries of the current day.
define_day() {
    day_begin="$(date --date "$(date --iso)" +"%s")"
    print_v "The day begins at $day_begin."
    day_end="$(date --date "$(date --iso) 23:59:59" +"%s")"
    print_v "The day ends at $day_end."
}

# Fetch geolocation information based on IP from ip-api.com
fetch_geo_data() {
    delete_old_files "geo"
    print_v "Fetching new geolocation data from the API."
    geo_data="$(curl -s \
        http://ip-api.com/json/\?fields=status,lat,lon,country,regionName,city)"

    new_geo_data_file="/tmp/geo_data_$(date +"%s").json"
    print_v "Saving geolocation data to file: $new_geo_data_file."
    printf '%s\n' "$geo_data" > "$new_geo_data_file"
}

# Fetch the Sunrise and Sunset data from https://sunrise-sunset.org/api
fetch_sun_data() {
    delete_old_files "sun"
    print_v "Fetching new sunrise and sunset data from the API"
    if [ -z "$lat" ] || [ -z "$lon" ]; then
        check_local_geo_data
        validate_geo_data
        populate_geo_vars
    fi
    sun_data="$(curl -s \
        https://api.sunrise-sunset.org/json\?lat="$lat"\&lng="$lon"\&formatted=0)"

    new_sun_data_file="/tmp/sun_data_$(date +"%s").json"
    print_v "Saving sunrise and sunset data to file: $new_sun_data_file."
    printf '%s\n' "$sun_data" > "$new_sun_data_file"
}

# Find data files in /tmp.
# Provide eith "geo" or "sun" as first argument to find files of that type.
find_data_files() {
    find /tmp -maxdepth 1 -name "${1}_data*.json" -user "$USER"
}

# Check to see if there is already local geo_data saved from a previous run.
check_local_geo_data() {
    geo_data_files="$(find_data_files "geo")"
    number_of_geo_data_files="$(find_data_files "geo" | wc -l)"

    print_v "The following old geo_data files were found:"
    print_v "$geo_data_files"
    print_v "Number of geo_data files: $number_of_geo_data_files"

    if [ ! "$number_of_geo_data_files" -eq 1 ]; then
        print_v "No geo_data file was found, or more than one was found."
        fetch_geo_data
        return
    fi

    local_geo_data_file_name="${geo_data_files[0]}"
    geo_data_file_time_with_ending="${local_geo_data_file_name##*\_}"
    geo_data_file_time="${geo_data_file_time_with_ending%\.*}"
    print_v "The local sun_data file time is $geo_data_file_time."

    # If there already is a file that has been fetched the last day,
    # then use it to avoid using the API.
    if [ "$geo_data_file_time" -ge "$day_begin" ] && \
       [ "$geo_data_file_time" -lt "$day_end" ]
    then
        print_v "geo_data file time is within current day."
        geo_data="$(cat "$local_geo_data_file_name")"
    else
        print_v "geo_data file time is NOT within current day."
        fetch_geo_data
    fi
}

# Check to see if there is already local sun_data saved from a previous run.
check_local_sun_data() {
    sun_data_files="$(find_data_files "sun")"
    number_of_sun_data_files="$(find_data_files "sun" | wc -l)"

    print_v "The following old sun_data files were found:"
    print_v "$sun_data_files"
    print_v "Number of sun_data files: $number_of_sun_data_files"

    if [ ! "$number_of_sun_data_files" -eq 1 ]; then
        print_v "No sun_data file was found, or more than one was found."
        fetch_sun_data
        return
    fi

    local_sun_data_file_name="${sun_data_files[0]}"
    sun_data_file_time_with_ending="${local_sun_data_file_name##*\_}"
    sun_data_file_time="${sun_data_file_time_with_ending%\.*}"
    print_v "The local sun_data file time is $sun_data_file_time."

    # If there already is a file that has been fetched the last day,
    # then use it to avoid using the API.
    if [ "$sun_data_file_time" -ge "$day_begin" ] && \
       [ "$sun_data_file_time" -lt "$day_end" ]
    then
        print_v "sun_data file time is within current day."
        sun_data="$(cat "$local_sun_data_file_name")"
    else
        print_v "sun_data file time is NOT within current day."
        fetch_sun_data
    fi
}

parse_geo_data_response() {
    jq --arg x "$1" '.[$x]' <<< "$geo_data" | sed 's/\"//g'
}

parse_sun_data_response() {
    if [ "$#" -eq 1 ]; then
        jq --arg x "$1" '.[$x]' <<< "$sun_data" | sed 's/\"//g'
    elif [ "$#" -eq 2 ]; then
        date_time="$(jq --arg x "$1" --arg y "$2" '.[$x][$y]' \
            <<< "$sun_data" | sed 's/\"//g')"
        # Transform to unix timestamp for easy math.
        date --date "$date_time" +"%s"
    else
        die "Illegal number of parameters to parse_sun_data_response."
    fi
}

set_wallpaper() {
    # Remove any trailing slash before trying to use the folder.
    trimmed_folder="${FOLDER%/}"
    wallpaper="${trimmed_folder}/${period}.jpg"

    print_v "Setting the wallpaper: $wallpaper."

    if [  ${cmd: -1} = "/" ]; then
        exec ${cmd}${wallpaper}
    else
        exec ${cmd} ${wallpaper}
    fi
}

take_a_guess() {
    hour="$(date +"%H")"

    case "$hour" in
       0[4-5])
           period="nautical_dawn" ;;
       0[6-7])
           period="civil_dawn" ;;
       0[8-9]|1[0-1])
           period="morning" ;;
       1[2-4])
           period="noon" ;;
       1[5-7])
           period="late_afternoon" ;;
       18)
           period="civil_dusk" ;;
       19|20)
           period="nautical_dusk" ;;
       *)
           period="night" ;;
    esac
}

# Error handling if the geo_data status is not "success".
validate_geo_data() {
    i=1
    while [ "$i" -le 3 ]; do
         print_v "Validation try: $i/3"
         geo_api_status="$(parse_geo_data_response status)"
         print_v "Geo API Status: $geo_api_status"

         if [ "$geo_api_status" != "success" ]; then
             print_v "The geo API request did not finish with a \"success\" status."
             print_v "Taking a guess on what time it could be."
             take_a_guess
             print_v "I think it might be: $period"
             set_wallpaper
             if [ "$i" -eq 3 ]; then
                 print_v "Too many failed geo validation attempts."
                 delete_old_files "geo"
                 exit 1
             fi
             print_v "Trying again in 10 seconds."
             sleep 10
             fetch_geo_data
             ((++i))
         else
             break
         fi
    done
}

# Error handling if the sun_data is not "OK".
validate_sun_data() {
    i=1
    while [ "$i" -le 3 ]; do
         print_v "Validation try: $i/3"
         api_status="$(parse_sun_data_response status)"
         print_v "Sun API Status: $api_status"

         if [ "$api_status" != "OK" ] || \
            [ "$(parse_sun_data_response results nautical_twilight_begin)" -lt "$day_begin" ]
         then
             print_v "Unable to determine the time based on the API response."
             print_v "Taking a guess on what time it could be."
             take_a_guess
             print_v "I think it might be: $period"
             set_wallpaper
             if [ "$i" -eq 3 ]; then
                 print_v "Too many failed sun validation attempts."
                 delete_old_files "sun"
                 exit 1
             fi
             print_v "Trying again in 10 seconds."
             sleep 10
             fetch_sun_data
             ((++i))
         else
             break
         fi
    done
}

# Populate $lat and $lon.
populate_geo_vars() {
    lat="$(parse_geo_data_response lat)"
    lon="$(parse_geo_data_response lon)"
    country="$(parse_geo_data_response country)"
    regionName="$(parse_geo_data_response regionName)"
    city="$(parse_geo_data_response city)"
    print_v "I think that I'm in $city, $regionName, $country."
    print_v "Using latitude: $lat"
    print_v "Using longitude: $lon"
}

# Populate the vars to compare against. In chronological order.
populate_time_vars() {
    naut_twi_begin="$(parse_sun_data_response results nautical_twilight_begin)"
    civ_twi_begin="$(parse_sun_data_response results civil_twilight_begin)"
    sunrise="$(parse_sun_data_response results sunrise)"
    noon="$(parse_sun_data_response results solar_noon)"
    sunset="$(parse_sun_data_response results sunset)"
    # I want to switch to another wallpaper when the afternoon is starting to
    # head toward sunset.
    length_of_afternoon=$((sunset-noon))
    late_afternoon=$((noon+(length_of_afternoon/4)*3))
    civ_twi_end="$(parse_sun_data_response results civil_twilight_end)"
    naut_twi_end="$(parse_sun_data_response results nautical_twilight_end)"

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
    [ -z "$period" ] && die "Unable to determine period"
}

verbose_summary() {
    if [ $verbose -eq 1 ]; then
        cat <<EOF
$(timestamp) Here follows a summary:
Nautical twilight begins at: $naut_twi_begin / $(to_time "$naut_twi_begin")
Civil twilight begins at:    $civ_twi_begin / $(to_time "$civ_twi_begin")
Sunrise is at:               $sunrise / $(to_time "$sunrise")
Noon is at:                  $noon / $(to_time "$noon")
Late afternoon begins at:    $late_afternoon / $(to_time "$late_afternoon")
Sunset is at:                $sunset / $(to_time "$sunset")
Civil twilight ends at:      $civ_twi_end / $(to_time "$civ_twi_end")
Nautical twilight ends at:   $naut_twi_end / $(to_time "$naut_twi_end")
The time is now:             $time / $(to_time "$time")
It's currently:              $period
EOF
    fi
}

while getopts "c:hpvx:y:f:" opt
   do
     case $opt in
        x) lat=$OPTARG;;
        y) lon=$OPTARG;;
        f) FOLDER=$OPTARG;;
        c) cmd=$OPTARG;;
        p) purge=1;;
        v) verbose=1;;
        h) usage 0;;
        *) usage 1;;
     esac
done

main() {
    verify_requirements
    purge_old_files
    define_day
    check_local_sun_data
    validate_sun_data
    populate_time_vars
    determine_period
    verbose_summary
    set_wallpaper
}

main
