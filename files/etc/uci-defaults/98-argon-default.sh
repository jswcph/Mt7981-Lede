#!/bin/sh

#=================================================
# Argon 默认主题配置
#=================================================

# 默认主题颜色
uci set argon.@global[0].primary_color='#4682B4'

# 登录页背景透明度
uci set argon.@global[0].transparency='0.3'

# 登录页背景模糊
uci set argon.@global[0].blur='0.5'

# 保存配置
uci commit argon

exit 0
