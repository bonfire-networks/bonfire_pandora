# bonfire_pandora in `extensions/`

Sviluppare **solo** sotto `extensions/bonfire_pandora/`, non sotto `deps/bonfire_pandora`.

In `config/deps.path`:

```text
bonfire_pandora = "extensions/bonfire_pandora"
```

Dopo `just mix deps.get`, Mix usa questo path.

## Repo Git (obbligatorio per commit / push)

La cartella `extensions/bonfire_pandora` deve essere un **clone Git** del repo (upstream o fork), **non** solo una copia di file senza `.git`.

Upstream ufficiale: [bonfire-networks/bonfire_pandora](https://github.com/bonfire-networks/bonfire_pandora), branch **`dev`**.

Verifica:

```bash
test -d extensions/bonfire_pandora/.git && git -C extensions/bonfire_pandora remote -v
```

Se **non** c’è `.git`, non puoi allinearti a GitHub né pushare: va creato il clone (o ricollegato il remote).

### Bootstrap consigliato (branch `dev`)

Dalla root dell’umbrella Bonfire:

```bash
cd extensions
mv bonfire_pandora bonfire_pandora.backup.$(date +%Y%m%d)   # se esiste già una cartella senza git
git clone -b dev https://github.com/bonfire-networks/bonfire_pandora.git bonfire_pandora
cd bonfire_pandora
# opzionale: fork su Gitea → git remote add gitea git@host:org/bonfire_pandora.git
```

Poi reintegra eventuali file solo-locali dal backup e committa **nel repo dell’estensione**.

### Dipendenza npm `plyr` (JS + CSS)

`plyr` **non** è più una dipendenza dell’umbrella `assets/package.json`: sta in **`bonfire_pandora/assets/package.json`**. Dopo aver aggiunto l’estensione, installa i pacchetti JS dell’estensione:

```bash
yarn --cwd extensions/bonfire_pandora/assets install
# oppure, se usi deps.path verso deps/:
yarn --cwd deps/bonfire_pandora/assets install
```

Il bundle esbuild dell’app risolve `import "plyr"` via `NODE_PATH` (vedi `assets/package.json` → `watch.js` / `build.esbuild`). Gli hook PanDoRa restano in questa estensione; **federated_archives** li aggrega nel flavour e re-esporta il CSS (vedi sotto).

### CSS Plyr (feed video preview)

Gli stili sono in `assets/css/pandora_plyr.css` (import da `../node_modules/plyr/` dell’estensione).

**Flavour Federated Archives:** nell’umbrella importa **`federated_archives/assets/css/federated_archives_plyr.css`** (re-export di questo file), non `pandora_plyr.css` direttamente — vedi README dell’estensione federated_archives.

**Installazione senza quel flavour:** puoi importare `pandora_plyr.css` una volta in `assets/css/app.css` (path adattato se l’estensione è sotto `deps/`).

**Documentazione unificata** (feed, `.prose`, bundle flat, click vs preview, file in `config/current_flavour/`): vedi nel repo **bonfire_lab**  
`docs_custom/bonfire_pandora/FEED_PLYR_CSS_E_INDIPENDENZA_UMBRELLA.md`.

### Nota su ambienti di lavoro (es. incus / recipe)

Alcune tree copiano i file dell’estensione **senza** la directory `.git`: servono per compilare o per documentazione, ma **non** sostituiscono il clone su cui fai `git commit`. Sul container o sulla macchina di sviluppo usa sempre un vero clone in `extensions/bonfire_pandora`.
