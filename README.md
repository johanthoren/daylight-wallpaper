# daylight-wallpaper
A simple script to set certain wallpapers at various times during the day
depending on the current daylight at your location. 

The script will try to guess the location if no coordinates are provided.
However, it's faster and more precise to set the coordinates manually as
described below.

You can use this with any type of pictures, but it works very well with landscape
photos that change as the day progresses, such as used by a very popular closed 
source operating system based in California. I'm sure you can find such pictures 
by using your favorite search engine, I don't want to include any for copyright 
reasons. But it will work with any images you seem fit. Just rename the files in 
accordance with the help text instructions.

## Example usage
I recommend using this with **cron** and a few environment variables as such:
``` sh
*/10 * * * * . $HOME/.profile; DISPLAY=:0 /usr/bin/bash $HOME/.local/bin/daylight_wallpaper.sh -x $LATITUDE -y $LONGITUDE -f $WALLPAPER_FOLDER
```

Set the `$LATITUDE`, `$LONGITUDE`, and `$WALLPAPER_FOLDER` variables in your
`~/.profile` or similar.

You can also write them out explicitly.

## Credit
This script uses the API at [Sunrise-Sunset](https://sunrise-sunset.org/api) as
well as [IP-API](https://ip-api.com/).
