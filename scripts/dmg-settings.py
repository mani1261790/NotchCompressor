# Evaluated by dmgbuild; paths are passed explicitly by create-dmg.sh.
format = 'UDZO'
filesystem = 'HFS+'
files = [defines['app']]
symlinks = {'Applications': '/Applications'}
background = defines['background']
window_rect = ((160, 120), (660, 400))
icon_locations = {'NotchCompressor.app': (180, 190), 'Applications': (480, 190)}
icon_size = 96
text_size = 14
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
