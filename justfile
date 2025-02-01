build:
    poetry run pelican content -s publishconf.py

dev:
    poetry run pelican --listen --autoreload
