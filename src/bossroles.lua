-- The role tags teams hand out at group bosses, as the list src/rolepicker lays out: each boss's name and its
-- tags, none longer than savedparty.MAX_TAG. Base tank is the picker's own tile, so no list repeats it.
return {
  -- Voker, the east and west players who go in, come out or charge alone, the south charger and the first
  -- and second north chargers.
  { name = "Amascut", tags = { "Voke", "EI", "WI", "EO", "WO", "ES", "WS", "SC", "G1", "G2" } },
  -- Backup and south chargers, north chargers, and the tanks of pets 1 and 3 and of pet 2.
  { name = "Durzag", tags = { "BUSC", "NC", "1/3", "PT2" } },
  -- North tank, poison tank, resuscitator, stun 5, shark 10 and double poison.
  { name = "Yakamaru", tags = { "NT", "PT", "CPR", "ST5", "SH10", "DBL" } },
  -- Hammer, minion tank, chinner, free damage, smoke cloud, and the Umbra and Glacies, Cruor and Fumus tanks.
  { name = "Angel of Death", tags = { "Ham", "MT", "Chin", "Free", "SC", "UG", "C", "F" } },
  -- Bomb tank, and top lure with the fifth bleed.
  { name = "Vorago", tags = { "Bomb", "TL5" } },
}
