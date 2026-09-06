#!/bin/sh

#=================================================
# Argon 默认主题配置
#=================================================
if [ ! -f /etc/config/argon ]; then
    touch /etc/config/argon
    uci add argon global
fi

uci set argon.@global[0].primary='#4682B4'
uci set argon.@global[0].dark_primary='#4A6B5D'
uci set argon.@global[0].mode='light'
uci set argon.@global[0].transparency='0.3'
uci set argon.@global[0].blur='0.5'
uci set argon.@global[0].blur_dark='0.5'
uci set argon.@global[0].transparency_dark='0.3'
uci set argon.@global[0].online_wallpaper='none'
uci commit argon
