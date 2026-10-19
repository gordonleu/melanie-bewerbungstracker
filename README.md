# Melanies Bewerbungs-Tracker

Online-Tracker mit Anmeldung, zentral gespeicherten Bewerbungen, privaten Unterlagen, Kennzahlen und Bewerbungsfluss.

Die Oberfläche wird mit GitHub Pages bereitgestellt. Datenbank, Anmeldung und private Dateien liegen in einem separaten Supabase-Projekt. Dieses Repository enthält keine Bewerbungen, Unterlagen, Passwörter oder geheimen Projektschlüssel.

## Nutzung

Mit dem freigeschalteten Konto anmelden. Änderungen werden zentral gespeichert und auf anderen geöffneten Geräten etwa alle 15 Sekunden oder beim Zurückwechseln aktualisiert. Während einer Bearbeitung wird ein neuer externer Stand gemeldet; ein veralteter Stand kann einen neueren nicht überschreiben.

Unterlagen: PDF, DOC/DOCX und gängige Bilder, maximal 20 MB je Datei und 100 MB pro Konto. Backups enthalten alle gespeicherten Bewerbungen und Unterlagen. Ein Import ersetzt den zentralen Stand auf allen Geräten. Für die einmalige Übernahme zuerst im alten lokalen Tracker exportieren und dann hier importieren.

## Betrieb

- `index.html`: vollständig gebündelte Webseite einschließlich Supabase JS 2.118.0; keine extern geladenen Skripte.
- `setup.sql`: getestete Initialstruktur für ein neues Supabase-Projekt. Freigeschaltete E-Mails werden ausschließlich in der privaten Datenbank gepflegt.
- `package.json` und `pnpm-lock.yaml`: festgelegte SDK-Version und Abhängigkeiten.
- `SUPABASE-LICENSE`: Lizenz des eingebundenen SDK.

Die Anmeldung verwendet E-Mail und Passwort. Ein angemeldeter Nutzer kann sein Passwort in der App ändern. Automatischer Passwort-Reset per E-Mail erfordert einen zusätzlich eingerichteten Mailversand. Ein Administrator kann den Zugang über Supabase verwalten.

Bei unterbrochenen Uploads können nicht zugeordnete Dateien im privaten Speicher verbleiben. Diese werden bei unklarer Speicherbestätigung bewusst nicht automatisch gelöscht, um Datenverlust zu vermeiden. Backups enthalten die zugeordneten Dateien; gelegentliche Speicherbereinigung ist administrativ möglich.
