build:
    poetry run pelican content -s publishconf.py

dev:
    poetry run pelican --listen --autoreload

publish: build
    git add .
    git commit
    git push
