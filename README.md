# Casters of Azeroth

> Voorheen **CasterKit**. Vanaf 0.5.0 zitten de questlijst, slimme questroute, GPS, pijl en route op de wereldkaart in de aparte add-on **Roads of Azeroth**; je instellingen gaan vanzelf mee. `/coa` en `/ck` werken allebei. Werkt samen met **Scrum of Azeroth**.

Caster-interface voor **WoW Forever** (client `_forever_`, interface 16001), gemaakt door **DinX**.
Werkt op een kale installatie, zonder ElvUI of Bartender4.

## Wat het doet

- **Actiebalken in één kader**: 1 tot 4 rijen onder elkaar, platte stijl, cooldowns met teller,
  rood buiten bereik, blauw bij te weinig mana. De gewone Blizzard-sneltoetsen blijven werken.
- **Rotatiehulp**: de knop die je nu best indrukt licht op (goud), de volgende zwak (geel),
  procs paars, defensief blauw. Plus een hintblokje boven de balken. AoE-modus via `/ck aoe`.
- **Racials**: Read Leyline bij weinig mana, Walk on Air bij vallen, ontsnap-racials als je vastzit,
  burst-racials (Berserking, Blood Fury, Eureka!) tijdens gevechten.
- **Levelen**: XP-balk met XP/uur, tijd tot level en kills tot level; in de tooltip van een vijand
  hoeveel kills je nog nodig hebt (gemeten of geschat); meldingen voor trainer en talentpunten;
  grijs verkopen en herstellen bij een verkoper.
- **Mage**: tellers voor conjured water, food en mana gems (klik = bijmaken), één klik eten en drinken,
  herinnering voor armor en Arcane Intellect, tip voor beter water bij de innkeeper.
- **Micromenu en tassen** samen in één paneel, met vrije tasplaatsen.
- **Lettertype**: standaard Roboto met een zachte schaduw (instelbaar).
- **Instellingen**: `/coa` (of `/ck`) of de minimapknop. Rechtsklik op de minimapknop = kaders verslepen.

## Binnen de regels

Alleen de officiële addon-API. Casters of Azeroth toont informatie en laat knoppen oplichten,
maar cast nooit zelf iets, verstuurt geen chatberichten en werkt niet met externe programma's.

## Structuur

| Bestand | Inhoud |
|---|---|
| `Core.lua` | instellingen, events, spreuk-, aura- en tashulpen, class-register, `/ck` |
| `Style.lua` | platte stijl (randen, iconen, knoppen) |
| `Bars.lua` | actiebalken (LibActionButton), sneltoetsen, Blizzard-balken verbergen |
| `MicroMenu.lua` | micromenu en tassen in één paneel |
| `Rotation.lua` | rotatiemotor, racials, glow op knoppen, hintblokje |
| `Leveling.lua` | XP-balk, tooltip "kills tot level", herinneringen, verkoper |
| `Classes/Mage.lua` | Frost/Fire/Arcane-prioriteiten, conjured food/water, buffs |
| `Map.lua` | wereldkaart: coördinaten, vervagen tijdens lopen, vlak kader, coördinaten op de minimap |
| `Config.lua` | instellingenvenster, minimapknop |

Een nieuwe class toevoegen: maak `Classes/<Class>.lua` met `CK:RegisterClass("TOKEN", { defaultSpec, specs, specOrder })`
en zet het in `CasterKit.toc`.

## Bibliotheken

`libs/` bevat LibStub (public domain), CallbackHandler-1.0, LibActionButton-1.0 en LibButtonGlow-1.0
(BSD-licentie, auteursvermelding in de bestanden zelf).
