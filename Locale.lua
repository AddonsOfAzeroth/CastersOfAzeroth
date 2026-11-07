-- CasterKit by DinX: translations. Code uses English strings as keys: L["Text"].
local _, ns = ...
local CK = ns.CK

CK.languages = { { "enUS", "English" }, { "nlNL", "Nederlands" } }

local NL = {}
CK.translations = { nlNL = NL }

-- Looked up at use time, so the saved language (loaded later) applies.
CK.L = setmetatable({}, {
	__index = function(_, key)
		local lang = CK.db and CK.db.language or "enUS"
		if key == "decimal" then return lang == "nlNL" and "," or "." end
		if key == "thousands" then return lang == "nlNL" and "." or "," end
		local t = CK.translations[lang]
		return t and t[key] or key
	end,
})

-- Dutch
local function add(t)
	for k, v in pairs(t) do NL[k] = v end
end
CK.AddTranslations = add

add({
	["%dh%02d"] = "%du%02d",
	["Keybind mode"] = "Keybind-modus",
	["Shift-click: keybind mode"] = "Shift-klik: keybind-modus",
	["Hover a button and press a key (Shift, Alt, Ctrl work too). Or use the Blizzard key bindings: row 1 = Action Bar, row 2 = Bottom Left, row 3 = Bottom Right, row 4 = Right."] = "Ga met de muis over een knop en druk een toets (ook met Shift, Alt, Ctrl). Of gebruik de Blizzard-sneltoetsen: rij 1 = Action Bar, rij 2 = Bottom Left, rij 3 = Bottom Right, rij 4 = Right.",
	["%d free bag slots left."] = "Nog %d vrije plaatsen in je tassen.",
	["%d talent point(s) available. Click to open your talents."] = "%d talentpunt(en) vrij. Klik om je talenten te openen.",
	["%s XP/h"] = "%s XP/u",
	["%s already manages the action bars. CasterKit bars are off; the rotation helper still lights up those buttons. Type /ck for settings."] = "%s beheert al de actiebalken. CasterKit-balken staan uit; de rotatiehulp licht wel op op die knoppen. Typ /ck voor instellingen.",
	[", solo value"] = ", solo-waarde",
	["/ck  settings\n/ck unlock  and  /ck lock  drag frames\n/ck aoe  toggle AoE mode\n/ck reset  reset positions"] = "/ck  instellingen\n/ck unlock  en  /ck lock  kaders verslepen\n/ck aoe  AoE-modus wisselen\n/ck reset  posities terugzetten",
	["A caster interface for WoW Forever: all action bars in one frame, a rotation helper that lights up the right button, and leveling helpers."] = "Een caster-interface voor WoW Forever: alle actiebalken in één kader, een rotatiehulp die de juiste knop laat oplichten, en hulpjes voor het levelen.",
	["About"] = "Over",
	["Action bars"] = "Actiebalken",
	["Also show the next spell (faint border)"] = "Volgende spreuk ook tonen (zwakke rand)",
	["Also via /ck aoe, middle-click on the minimap button or your own key binding."] = "Ook via /ck aoe, middelklik op de minimapknop of een eigen sneltoets.",
	["AoE mode (multiple enemies)"] = "AoE-modus (meerdere vijanden)",
	["AoE mode off (single target)."] = "AoE-modus uit (één doelwit).",
	["AoE mode on."] = "AoE-modus aan.",
	["Arcane Intellect is missing."] = "Arcane Intellect ontbreekt.",
	["At a vendor"] = "Bij een verkoper",
	["Background behind the bars"] = "Achtergrond achter de balken",
	["Bags in the same panel"] = "Tassen in hetzelfde paneel",
	["Blizzard glow"] = "Blizzard-glinster",
	["Button size"] = "Knopgrootte",
	["Buttons per row"] = "Knoppen per rij",
	["Cast bar"] = "Castbar",
	["CasterKit bars: drag me\n/ck lock to lock"] = "CasterKit-balken: sleep mij\n/ck lock om te vergrendelen",
	["CasterKit chat (IRC style)"] = "CasterKit-chat (IRC-stijl)",
	["CasterKit only shows which button to press. You press it yourself: nothing is ever cast automatically."] = "CasterKit toont alleen welke knop je best indrukt. Jij drukt zelf: er wordt nooit iets automatisch gecast.",
	["CasterKit only uses the official addon API. It shows information and lights up buttons, but never casts anything itself, never sends chat messages and does not work with external programs."] = "CasterKit gebruikt alleen de officiële addon-API. Het toont informatie en laat knoppen oplichten, maar cast nooit zelf iets, verstuurt geen chatberichten en werkt niet samen met externe programma's.",
	["Character, spellbook, talents, quests… tidy in one panel."] = "Personage, spreukenboek, talenten, quests… netjes in één kader.",
	["Class color on the health bar"] = "Klassekleur op de levensbalk",
	["Click: "] = "Klik: ",
	["Click: settings"] = "Klik: instellingen",
	["Colors: gold = press now, purple = proc (e.g. Fingers of Frost), blue = defensive (falling, rooted, too close)."] = "Kleuren: goud = nu indrukken, paars = proc (bv. Fingers of Frost), blauw = defensief (vallen, vastzitten, te dichtbij).",
	["Commands"] = "Commando's",
	["Conjured food: %d. Click to conjure more."] = "Conjured food: %d. Klik om bij te maken.",
	["Conjured water: %d. Click to conjure more."] = "Conjured water: %d. Klik om bij te maken.",
	["Current"] = "Huidig",
	["Dead"] = "Dood",
	["Eat and drink: click to use your conjured food and water."] = "Eten en drinken: klik om je conjured food en water te gebruiken.",
	["ElvUI (action bars)"] = "ElvUI (actiebalken)",
	["Experience"] = "Ervaring",
	["Fade tabs until you hover them"] = "Tabbladen vervagen tot je eroverheen gaat",
	["Failed"] = "Mislukt",
	["Font size"] = "Lettergrootte",
	["Frames locked"] = "Kaders vergrendeld",
	["Frames locked."] = "Kaders vergrendeld.",
	["Frames unlocked: drag them where you like, type /ck lock when done."] = "Kaders ontgrendeld: sleep ze waar je wil, typ /ck lock als je klaar bent.",
	["General"] = "Algemeen",
	["General, Guild, Whisper, Trade, LFG, Combat. Asked once."] = "Algemeen, Gilde, Fluister, Handel, LFG, Gevecht. Wordt één keer gevraagd.",
	["Ghost"] = "Geest",
	["Height"] = "Hoogte",
	["Hidden Blizzard frames only come back after a reload. Unlock the frames (General) to drag them."] = "Blizzard-frames die verborgen zijn, komen pas terug na een herlaad. Ontgrendel de kaders (Algemeen) om frames te verslepen.",
	["Hide Blizzard XP bar"] = "Blizzard-XP-balk verbergen",
	["Hide Blizzard bars"] = "Blizzard-balken verbergen",
	["Hide Blizzard cast bar"] = "Blizzard-castbar verbergen",
	["Hides the default bars that CasterKit replaces."] = "Verbergt de standaardbalken die CasterKit vervangt.",
	["Hint box above the bars"] = "Hintblokje boven de balken",
	["In combat Blizzard hides many values from addons. Blizzard's own suggestion always works; the own priority falls back to Blizzard when something is hidden."] = "Blizzard schermt in gevechten veel waarden af voor addons. De suggestie van Blizzard zelf werkt altijd; de eigen prioriteit valt terug op Blizzard als iets afgeschermd is.",
	["Interrupted"] = "Onderbroken",
	["Kills to level in enemy tooltips"] = "Kills tot level in de tooltip van vijanden",
	["Language"] = "Taal",
	["Level %d: new spells are waiting at your trainer."] = "Level %d: er zijn nieuwe spreuken bij je trainer.",
	["Level %d: new spells at your trainer!"] = "Level %d: nieuwe spreuken bij je trainer!",
	["Leveling"] = "Levelen",
	["Light up buttons"] = "Knoppen laten oplichten",
	["Main bar (1 to =) on top"] = "Hoofdbalk (1 t/m =) bovenaan",
	["Micro menu"] = "Micromenu",
	["Micro menu and bags"] = "Micromenu en tassen",
	["Micro menu in a CasterKit panel"] = "Micromenu in een CasterKit-paneel",
	["Middle-click: AoE mode"] = "Middelklik: AoE-modus",
	["Names in class color"] = "Namen in klassekleur",
	["No armor buff active."] = "Geen armor-buff actief.",
	["No longer gives XP"] = "Geeft geen XP meer",
	["No mana gem in your bags."] = "Geen mana gem in je tassen.",
	["No other action bar addon active."] = "Geen andere actiebalk-addon actief.",
	["Notify: new spells at the trainer"] = "Melding: nieuwe spreuken bij de trainer",
	["Notify: talent points available"] = "Melding: talentpunten vrij",
	["One tab per channel"] = "Tabblad per kanaal",
	["Only with a hostile target"] = "Alleen bij een vijandig doelwit",
	["Open CasterKit settings"] = "Open CasterKit-instellingen",
	["Open settings"] = "Open instellingen",
	["Orange = interruptible (Counterspell), grey with lock = not."] = "Oranje = onderbreekbaar (Counterspell), grijs met slot = niet.",
	["Own cast bar"] = "Eigen castbar",
	["Own priority (guide)"] = "Eigen prioriteit (guide)",
	["Party"] = "Groep",
	["Player"] = "Speler",
	["Positions and bar settings reset."] = "Posities en balkinstellingen teruggezet.",
	["Pulsing border"] = "Pulserende rand",
	["Reload UI"] = "Interface herladen",
	["Reload the UI to apply the language everywhere."] = "Herlaad de interface om de taal overal toe te passen.",
	["Reload your UI (/reload) to see the Blizzard cast bar again."] = "Herlaad je UI (/reload) om de Blizzard-castbar terug te zien.",
	["Reminders (water, food, buffs, bags…)"] = "Herinneringen (water, food, buffs, tassen…)",
	["Repair automatically"] = "Automatisch herstellen",
	["Repaired your gear for %s."] = "Uitrusting hersteld voor %s.",
	["Replaces Blizzard's player, target and party frames."] = "Vervangt de speler-, doelwit- en groepsframes van Blizzard.",
	["Reset positions"] = "Posities terugzetten",
	["Right-click: lock/unlock frames"] = "Rechtsklik: kaders (ont)grendelen",
	["Rotation"] = "Rotatie",
	["Rotation for"] = "Rotatie voor",
	["Rotation helper"] = "Rotatiehulp",
	["Rotation helper on"] = "Rotatiehulp aan",
	["Rotation: "] = "Rotatie: ",
	["Rows"] = "Aantal rijen",
	["Scale"] = "Schaal",
	["Sell grey items automatically"] = "Grijze items automatisch verkopen",
	["Set key bindings in the normal Blizzard menu (Keybindings). Row 1 = Action Bar, row 2 = Bottom Left, row 3 = Bottom Right, row 4 = Right."] = "Sneltoetsen stel je in via het gewone Blizzard-menu (Toetsenbord). Rij 1 = Action Bar, rij 2 = Bottom Left, rij 3 = Bottom Right, rij 4 = Right.",
	["Short channel names ([T], [G], [g]…)"] = "Korte kanaalnamen ([T], [G], [g]…)",
	["Show latency at the end"] = "Latency tonen aan het einde",
	["Show minimap button"] = "Minimapknop tonen",
	["Sold %d grey item(s) for %s."] = "%d grijze item(s) verkocht voor %s.",
	["Spacing"] = "Tussenruimte",
	["Start over"] = "Opnieuw beginnen",
	["Still needed"] = "Nog nodig",
	["Style"] = "Stijl",
	["Suggestion source"] = "Bron van de suggestie",
	["Target"] = "Doelwit",
	["Target (with your debuffs)"] = "Doelwit (met jouw debuffs)",
	["Target cast bar"] = "Doelwit-castbar",
	["The red part: from there you can already press your next spell."] = "Het rode stuk: vanaf daar mag je je volgende spreuk al indrukken.",
	["There is no rotation for your class yet. Bars and leveling helpers still work."] = "Voor jouw class is er nog geen rotatie. De balken en levelhulpjes werken wel.",
	["This session"] = "Deze sessie",
	["Timestamps [14:03]"] = "Tijdstempels [14:03]",
	["Tip: the innkeeper now sells %s, better than your own Conjure Water until your next rank."] = "Tip: vanaf nu verkoopt de innkeeper %s, beter dan je eigen Conjure Water tot je volgende rank.",
	["Toggle AoE mode"] = "Wissel AoE-modus",
	["Turn off to drag the bars, hint box, frames and micro menu."] = "Zet uit om de balken, het hintblokje en het micromenu te verslepen.",
	["Turning this off needs a reload to give the Blizzard bars back."] = "Uitzetten vraagt een herlaad om de Blizzard-balken terug te geven.",
	["Unlock the frames (General) to drag the panel."] = "Ontgrendel de kaders (Algemeen) om het paneel te verslepen.",
	["Use CasterKit action bars"] = "CasterKit-actiebalken gebruiken",
	["Use CasterKit frames"] = "CasterKit-frames gebruiken",
	["Version %s, made by DinX."] = "Versie %s, gemaakt door DinX.",
	["Width"] = "Breedte",
	["With the number of free slots on your backpack."] = "Met het aantal vrije plaatsen op je rugzak.",
	["Within the rules"] = "Binnen de regels",
	["XP bar with XP per hour and time to level"] = "XP-balk met XP per uur en tijd tot level",
	["Your gear is worn. Repair at a vendor."] = "Je uitrusting is versleten. Laat herstellen bij een verkoper.",
	["estimated"] = "geschat",
	["measured"] = "gemeten",
	["off"] = "uit",
	["on"] = "aan",
	["|cffff5050%s currently manages the action bars.|r Disable it to use the CasterKit bars; meanwhile the rotation helper works on those buttons."] = "|cffff5050%s beheert nu de actiebalken.|r Zet dat uit om de CasterKit-balken te gebruiken; de rotatiehulp werkt intussen op die knoppen.",
	["±%d kills to level %d (%s%s)"] = "±%d kills tot level %d (%s%s)",
})

add({
	["Hover a button and press a key. Shift, Alt and Ctrl work too. Delete clears. Esc to finish."] = "Ga met de muis over een knop en druk een toets. Shift, Alt en Ctrl werken ook. Delete wist. Esc om te stoppen.",
	["Save for this character only"] = "Alleen voor dit personage opslaan",
	["Done"] = "Klaar",
	["Mouse buttons 4/5, middle click and the mouse wheel work too."] = "Muisknoppen 4/5, middelste klik en het muiswiel werken ook.",
	["Keys: %s"] = "Toetsen: %s",
	["No key bound"] = "Geen toets ingesteld",
	["%s is already bound to %s."] = "%s is al gekoppeld aan %s.",
	["Could not bind %s."] = "Kon %s niet koppelen.",
	["%s replaced: %s"] = "%s vervangen: %s",
	["%s bound to %s."] = "%s gekoppeld aan %s.",
	["Keys cleared: %s"] = "Toetsen gewist: %s",
	["Keybind mode is not available in combat."] = "Keybind-modus is niet beschikbaar in gevecht.",
	["No CasterKit action buttons to bind."] = "Geen CasterKit-actieknoppen om te koppelen.",
	["Keybind mode closed: you entered combat."] = "Keybind-modus gesloten: je bent in gevecht.",
})

add({
})

add({
	["Tooltips"] = "Tooltips",
	["Show tooltips at a fixed spot"] = "Tooltips op een vaste plek tonen",
	["Spell explanations and unit info appear in a corner instead of over your screen. Unlock the frames to move the spot."] = "Uitleg van spreuken en info over personages komt in een hoek in plaats van over je beeld. Ontgrendel de kaders om de plek te verplaatsen.",
	["No action bar tooltips in combat"] = "Geen tooltips van actieknoppen in gevecht",
	["Guild"] = "Gilde",
	["Whisper"] = "Fluister",
	["Trade"] = "Handel",
	["Copy chat"] = "Kopieer chat",
	["Shows the last 100 lines of this tab, ready to copy."] = "Toont de laatste 100 regels van dit tabblad, klaar om te kopiëren.",
	["Select all with Ctrl+A, copy with Ctrl+C."] = "Alles selecteren met Ctrl+A, kopiëren met Ctrl+C.",
	["%d protected lines were left out."] = "%d beschermde regels zijn weggelaten.",
	["Press Enter to chat"] = "Druk op Enter om te chatten",
	["Scroll to the bottom"] = "Naar de nieuwste regel",
	["CasterKit will set up your chat with one tab per channel. Continue?"] = "CasterKit zet je chat op met een tabblad per kanaal. Doorgaan?",
	["Chat tabs are set up."] = "Chattabbladen zijn ingesteld.",
	["No free chat window left for more tabs."] = "Geen vrij chatvenster meer voor extra tabbladen.",
	["%s already manages the chat; the CasterKit chat stays off."] = "%s beheert de chat al; de CasterKit-chat blijft uit.",
	["Turning the chat off takes effect after /reload."] = "De chat uitschakelen werkt pas na /reload.",
})

add({
	["Profiles"] = "Profielen",
	["Save the settings of this character under a name and use them on your alts. Personal things (spec, measured XP, chat setup) stay with each character."] = "Bewaar de instellingen van dit personage onder een naam en gebruik ze op je alts. Persoonlijke dingen (spec, gemeten XP, chat-setup) blijven bij elk personage.",
	["Current profile: %s"] = "Huidig profiel: %s",
	["none"] = "geen",
	["Save"] = "Bewaren",
	["Profile name"] = "Naam van het profiel",
	["Save current settings"] = "Huidige instellingen bewaren",
	["Profile saved: %s"] = "Profiel bewaard: %s",
	["Use a profile"] = "Een profiel gebruiken",
	["Profile"] = "Profiel",
	["Load into this character"] = "Laden op dit personage",
	["Profile loaded: %s. Reloading the UI…"] = "Profiel geladen: %s. De interface wordt herladen…",
	["Delete"] = "Verwijderen",
	["Use this profile for new characters"] = "Dit profiel gebruiken voor nieuwe personages",
	["A new alt starts with these settings at its first login."] = "Een nieuwe alt begint met deze instellingen bij de eerste login.",
})

add({
	["Conjured water: %d"] = "Conjured water: %d",
	["Conjured food: %d"] = "Conjured food: %d",
	["Mana gem"] = "Mana gem",
	["Left-click: use %s"] = "Linksklik: %s gebruiken",
	["Right-click: "] = "Rechtsklik: ",
})

add({
	["Dampen Magic is missing (solo: less magic damage taken)."] = "Dampen Magic ontbreekt (solo: minder magische schade).",
})

-- Key bindings (Bindings.xml); names are read before saved settings load, so English
BINDING_HEADER_CASTERKIT = "CasterKit"
BINDING_NAME_CASTERKIT_AOE = "Toggle AoE mode"
BINDING_NAME_CASTERKIT_CONFIG = "Open settings"
