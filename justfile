build:
    poetry run pelican content -s publishconf.py

run:
    poetry run pelican --listen --autoreload
