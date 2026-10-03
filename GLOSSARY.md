# AI Usage

Eine macOS-Menüleisten-App, die auf einen Blick zeigt, wie viel von den Nutzungslimits der eigenen KI-Abos schon verbraucht ist und ob man im Takt liegt.

## Provider und Limits

**Provider**:
Ein KI-Dienst, dessen Limits die App anzeigt; jeder Provider ist ein Tab. Claude ist der erste, weitere (z. B. Codex) folgen später.
_Avoid_: Anbieter, Service, Account

**Limit**:
Ein Nutzungskontingent eines Providers, bestehend aus Fenster, Auslastung und Reset-Zeitpunkt.
_Avoid_: Kontingent, Quota, Budget

**Fenster**:
Der Zeitraum, über den ein Limit gemessen wird (z. B. 5 Stunden oder 7 Tage), bis es zurückgesetzt wird.
_Avoid_: Zyklus, Periode, Takt

**Auslastung**:
Wie viel Prozent eines Limits im aktuellen Fenster verbraucht sind.
_Avoid_: Usage, Verbrauch, Utilization

**Reset-Zeitpunkt**:
Der Moment, in dem das aktuelle Fenster endet und die Auslastung auf null zurückfällt.
_Avoid_: Ablauf, Erneuerung

### Limits von Claude

**Session-Limit**:
Claudes Limit mit 5-Stunden-Fenster (in Claude "Current session").
_Avoid_: Stundenkontingent, Stundenlimit, 5h-Limit

**Wochenlimit**:
Claudes Limit mit 7-Tage-Fenster über alle Modelle.
_Avoid_: Wochenkontingent

**Fable-Limit**:
Claudes modellspezifisches Wochenlimit, das nur die Nutzung von Fable zählt.
_Avoid_: Fable usage, Fable-Kontingent

## Pace

**Pace**:
Die Auslastung, die man jetzt hätte, wenn man gleichmäßig über das ganze Fenster verbrauchen würde, also der bereits verstrichene Anteil des Fensters.
_Avoid_: Soll, Takt, Sollwert

**Pace-Marker**:
Der Strich auf dem Balken eines Limits, der die Pace anzeigt.
_Avoid_: Soll-Linie, Markierung

**Voraus**:
Die Auslastung liegt über der Pace: Bei gleichem Tempo ist das Limit vor dem Reset-Zeitpunkt erschöpft.
_Avoid_: drüber, zu schnell

**Hinterher**:
Die Auslastung liegt unter der Pace: Es bleibt Reserve bis zum Reset-Zeitpunkt.
_Avoid_: drunter, Puffer
