# ClickLegend

On-screen legend and tooltips for your click-cast bindings in World of Warcraft (WoW Forever).
Reads Clique, VuhDo, HealBot, EllesmereUI HoverCast and the game's own Click Casting.

- One icon per bound key or button, with the ally spell and the enemy spell.
- Hold Shift, Ctrl or Alt to see that modifier's bindings, or show every layer at once.
- Unit tooltips list the bindings for the hovered frame.
- Read-only: it never changes bindings and uses no secure frames.

Type `/clg` in game for settings. See `README.txt` for the full command list and `CHANGELOG.md` for changes.

## Releasing

Releases are built by [BigWigsMods/packager](https://github.com/BigWigsMods/packager) from `.github/workflows/release.yml`.

1. Add the new version's notes to the top of `CHANGELOG.md` and commit.
2. Tag the commit with the version number and push the tag:

   ```
   git tag -a 1.6.0 -m "1.6.0"
   git push origin 1.6.0
   ```

The tag name becomes the addon version (`@project-version@` in the TOC), the zip is uploaded to CurseForge, and a GitHub release is created.

## License

MIT. ClickLegend is an independent addon and is not affiliated with EllesmereUI, Clique, VuhDo or HealBot.
