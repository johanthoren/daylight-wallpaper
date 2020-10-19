# daylight-wallpaper
A simple script to set certain wallpapers at various times during the day
depending on the current daylight at your location. 

I'm using these with a collection of MacOS Big Sur wallpapers that I found 
online. I'm sure you can find it by using your favorite search engine, I don't 
want to include them for copyright reasons. But it will work with any images you
seem fit. Just rename the files in accordance with the help text instructions.

## Example usage
I recommend using this with **cron** and a few environment variables as such:
``` sh
*/10 * * * * . $HOME/.profile; DISPLAY=:0 /usr/bin/bash $HOME/.local/bin/daylight_wallpaper.sh -x $LATITUDE -y $LONGITUDE -f $WALLPAPER_FOLDER
```

Set the `$LATITUDE`, `$LONGITUDE`, and `$WALLPAPER_FOLDER` variables in your
`~/.profile` or similar.

You can also write them out explicitly.

## Credit
This script uses the API at [Sunrise-Sunset](https://sunrise-sunset.org/api).
