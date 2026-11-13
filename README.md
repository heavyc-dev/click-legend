# ClickLegend

Better click casting for World of Warcraft (WoW Forever), on the default raid frames or any unit frames that support click casting, with an on-screen legend of every binding.

- Rules per key: the first that fits is cast. Dead ally, ally and enemy on one key; conditions for combat, stance or form, pet and an extra modifier. Picked from lists, no macros to write.
- Mouse buttons, the wheel and keyboard keys. A guided setup, Quickbind (point at a spell, press a key), starter sets for every class, sets shared across characters, a set per spec, export and import.
- A key can work on any unit under the cursor, not only on unit frames. Dispel and Resurrect actions that pick the right spell for your class. Macro text in a rule, a trinket or stop-cast before a spell, casting on the press.
- Works on the game's own frames and on frames other addons offer for click casting (EllesmereUI among them).
- The legend: one icon per bound key or button with the ally spell and the enemy spell, modifier layers, and unit tooltip lines. Spells you cannot cast right now (cooldown, mana, range) are dimmed. It also reads Clique, VuhDo, HealBot, EllesmereUI HoverCast and the game's own Click Casting.
- Click casting is off until you switch it on. Until then the addon only reads and draws: it changes no bindings and touches no unit frame.

Type `/clg` in game for settings. See `README.txt` for the full command list and `CHANGELOG.md` for changes.

## Releasing

CurseForge packages this repository itself when a tag is pushed (GitHub webhook). `.pkgmeta` controls what goes into the zip.

1. Add the new version's notes to the top of `CHANGELOG.md`, commit and push.
2. Tag the commit with the version number and push the tag:

   ```
   git tag -a X.Y.Z -m "X.Y.Z"
   git push origin X.Y.Z
   ```

The tag name becomes the addon version (`@project-version@` in the TOC) and CurseForge publishes the build with the changelog as its release notes.

## License

MIT. ClickLegend is an independent addon and is not affiliated with EllesmereUI, Clique, VuhDo or HealBot.
