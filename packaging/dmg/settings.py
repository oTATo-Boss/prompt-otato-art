"""Finder layout for the oTATo prompt drag-to-install disk image."""

from pathlib import Path

app = Path(defines["app"]).expanduser().resolve()
if not app.is_dir() or app.suffix != ".app":
    raise ValueError("Pass an existing .app bundle with -D app=/path/to/app")

assets = Path(defines.get("assets", "packaging/dmg")).expanduser().resolve()
format = "UDZO"
filesystem = "HFS+"
files = [str(app)]
symlinks = {"应用程序": "/Applications"}
background = str(assets / "background.png")

# Points; background@2x.png supplies the matching Retina representation.
window_rect = ((220, 180), (768, 544))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
arrange_by = None
grid_spacing = 90
icon_size = 120
text_size = 14
label_pos = "bottom"
icon_locations = {app.name: (229, 231), "应用程序": (555, 231)}
