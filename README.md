# daylight-wallpaper
A simple script to set certain wallpapers at various times during the day
depending on the current daylight at your location.

## Example usage
I recommend using this with **cron** and a few environment variables as such:
``` sh
*/15 * * * * DISPLAY=:0 /usr/bin/bash /home/username/bin/daylight_wallpaper.sh -x $LATITUDE -y $LONGITUDE -f $WALLPAPER_FOLDER
```

Set the `$LATITUDE`, `$LONGITUDE`, and `$WALLPAPER_FOLDER` variables in your
`~/.profile` or similar.

You can also write them out explicitly.

## Credit
This script uses the API at [Sunrise-Sunset](https://sunrise-sunset.org/api).
