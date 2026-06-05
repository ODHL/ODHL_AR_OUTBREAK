#!/usr/bin/env bash
# run_ob_prep.sh  —  Prepare an outbreak analysis run for ODHL_AR_OUTBREAK.
#
# Usage:
#   bash run_ob_prep.sh <PROJECT_ID>
#
# Required files in $OB_DIR (this script's directory):
#   samples.csv     — one source sample ID per line (YYARNNNN[REPEAT] format).
#                     May also be tab/comma-delimited with species or notes after the ID.
#   extra_meta.tsv  — (optional) TSV with specimen_id, isolation_source, collect_date
#                     for samples not yet in ar_pass.tsv.
#
# Environment overrides (all have defaults):
#   OB_DIR          — directory containing this script and input files
#   AR_PASS_TSV     — path to ar_pass.tsv  (default: shared ODHL_AR assets)
#   DB_MASTER_CSV   — path to db_master.csv (default: shared ODHL_AR assets)
#   TARGET_TOTAL    — max total samples in outbreak analysis (default: 35)
#   PROJECT         — project ID (default: first positional arg or OB<YYMMDD>)
#
# Outputs written to $HOME/output/<PROJECT>/input/:
#   samplesheet.csv                    — source samples for arANALYZER
#   samplesheet_gff.csv                — same samples, for GFF filtering
#   labResults.csv                     — sample → species map for QC
#   ref_samples.csv                    — reference sample IDs selected from reference_outdir
#   <PROJECT>_metadata.csv             — NCBI-style metadata for source samples
#   run_OUTBREAK_ANALYZER.sh           — single executable that runs the full pipeline

set -euo pipefail

OB_DIR="${OB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OB_WF_DIR="$(cd "$OB_DIR/.." && pwd)"

# ── BaseSpace access helpers ──────────────────────────────────────────────────

declare -A BS_ACCESS_CACHE
BS_BIN=""

resolve_basespace_cli() {
  if [[ -n "$BS_BIN" ]]; then return 0; fi
  local bs="${BS:-}"
  if [[ -z "$bs" ]]; then
    if command -v basespace >/dev/null 2>&1; then
      bs="$(command -v basespace)"
    elif [[ -x "$HOME/tools/basespace" ]]; then
      bs="$HOME/tools/basespace"
    fi
  fi
  [[ -x "$bs" ]] || { echo "ERROR: basespace CLI not found" >&2; return 1; }
  BS_BIN="$bs"
}

project_is_accessible() {
  local proj="$1"
  proj="${proj%_AR}"
  if [[ -n "${BS_ACCESS_CACHE[$proj]+x}" ]]; then
    [[ "${BS_ACCESS_CACHE[$proj]}" == "ok" ]]
    return
  fi
  resolve_basespace_cli || return 1
  local result
  result=$("$BS_BIN" list projects --filter-field Name --filter-term "$proj" 2>/dev/null || true)
  if echo "$result" | grep -q "$proj"; then
    BS_ACCESS_CACHE[$proj]="ok"; return 0
  fi
  BS_ACCESS_CACHE[$proj]="fail"; return 1
}

check_basespace_access() {
  local input_csv="$1"
  resolve_basespace_cli || return 1

  mapfile -t projects < <(
    awk -F',' 'NR>1 && $3!="" { p=$3; sub(/_AR$/, "", p); print p }' "$input_csv" | sort -u
  )

  local total="${#projects[@]}" ok=0 fail=0
  local failed=()

  echo "Checking BaseSpace access for $total project(s)..."
  echo

  for proj in "${projects[@]}"; do
    if project_is_accessible "$proj"; then
      echo "  OK          $proj"
      (( ok++ )) || true
    else
      echo "  NO ACCESS   $proj"
      failed+=("$proj")
      (( fail++ )) || true
    fi
  done

  echo
  echo "########################################"
  echo "accessible:   $ok / $total"
  if [[ "$fail" -eq 0 ]]; then
    echo "All projects accessible - ready to run."
  else
    echo "Need access to $fail project(s):"
    for p in "${failed[@]}"; do echo "  $p"; done
  fi
  echo "########################################"

  [[ "$fail" -eq 0 ]]
}

# Shared database assets — fall back to sibling ODHL_AR install if not in OB_WF_DIR
_SHARED_ASSETS=""
if [[ -d "$OB_WF_DIR/assets/databases" ]]; then
  _SHARED_ASSETS="$OB_WF_DIR/assets"
elif [[ -d "$OB_WF_DIR/../ODHL_AR/assets" ]]; then
  _SHARED_ASSETS="$OB_WF_DIR/../ODHL_AR/assets"
else
  echo "WARN: Cannot locate shared assets directory; set AR_PASS_TSV and DB_MASTER_CSV manually." >&2
  _SHARED_ASSETS="$OB_WF_DIR/assets"
fi

SAMPLES_FILE="${SAMPLES_FILE:-$OB_DIR/samples.csv}"
AR_PASS_TSV="${AR_PASS_TSV:-$_SHARED_ASSETS/databases/ar_pass/ar_pass.tsv}"
DB_MASTER_CSV="${DB_MASTER_CSV:-$_SHARED_ASSETS/databases/IDdbs/db_master.csv}"
EXTRA_TSV="${EXTRA_TSV:-$OB_DIR/extra_meta.tsv}"
TARGET_TOTAL="${TARGET_TOTAL:-35}"
PROJECT="${1:-${PROJECT:-OB$(date +%y%m%d)}}"

TMP_DIR="$OB_DIR/tmp"
OUTDIR="$HOME/output/$PROJECT/input"
mkdir -p "$TMP_DIR" "$OUTDIR"

SOURCE_IDS="$TMP_DIR/source_ids.txt"
SOURCE_RESOLVED="$TMP_DIR/source_resolved.csv"
SOURCE_MISSING="$TMP_DIR/source_missing.txt"
REF_SELECTED="$TMP_DIR/ref_selected.csv"
SELECTED_ALL="$TMP_DIR/selected_samples.csv"
SELECTED_META="$TMP_DIR/selected_for_metadata.csv"
MATCHED_DB="$TMP_DIR/matched_database.csv"
REF_SAMPLES="$OUTDIR/ref_samples.csv"
METADATA_OUT="$TMP_DIR/metadata_for_script.csv"
MISSING_META="$TMP_DIR/missing_samples.txt"

: > "$SOURCE_IDS"
: > "$SOURCE_RESOLVED"
: > "$SOURCE_MISSING"
: > "$REF_SELECTED"
: > "$SELECTED_ALL"
: > "$SELECTED_META"
: > "$MATCHED_DB"
: > "$METADATA_OUT"
: > "$MISSING_META"

# ── Validate required inputs ──────────────────────────────────────────────────

[[ -f "$SAMPLES_FILE" ]] || { echo "ERROR: samples file not found: $SAMPLES_FILE" >&2; exit 1; }
[[ -f "$AR_PASS_TSV" ]]  || { echo "ERROR: ar_pass TSV not found: $AR_PASS_TSV" >&2; exit 1; }

if [[ ! -f "$EXTRA_TSV" ]]; then
  echo "WARN: extra_meta.tsv not found: $EXTRA_TSV (fallback limited)" >&2
  EXTRA_TSV=""
fi
if [[ ! -f "$DB_MASTER_CSV" ]]; then
  echo "WARN: db_master.csv not found: $DB_MASTER_CSV (will rely on ar_pass only)" >&2
  DB_MASTER_CSV=""
fi

# ── Helper: build metadata CSV ────────────────────────────────────────────────

build_metadata_csv() {
  local samples_file="$1" arpass_tsv="$2" extra_tsv="$3"
  local db_csv="$4" out_csv="$5" missing_csv="$6"

  cat > "$out_csv" <<'HDR'
sample_id,basespace_collection_id,specimen_id,wgs_id,srr_number,wgs_date_put_on_sequencer,sequence_classification,filler1,filler2,filler3,isolation_source,filler4,filler5,collection_date,trailing_col
HDR
  printf 'sampleID,species,projectID\n' > "$missing_csv"

  awk -v SAMPLES="$samples_file" -v MASTER="$arpass_tsv" -v EXTRA="$extra_tsv" \
      -v DBM="$db_csv" -v OUTFILE="$out_csv" -v MISSFILE="$missing_csv" '
function up(s){ return toupper(s) }
function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
function trim(s){ return ltrim(rtrim(s)) }
function csv(f){ gsub(/\r$/,"",f); gsub(/"/,"\"\"",f); if(f ~ /[", ]/) return "\"" f "\""; return f }
function is_id(s){ s=up(trim(s)); return (s ~ /^[0-9]{2}AR[0-9]+(REPEAT)?([_-].*)?$/) }
function canon_id(s){ s=up(trim(s)); sub(/[_-].*/, "", s); sub(/REPEAT$/, "", s); return s }
function is_date(s){ s=trim(s); return (s ~ /^[0-9]{2}[-\/][0-9]{2}[-\/][0-9]{4}$/ || s ~ /^[0-9]{4}[-\/][0-9]{2}[-\/][0-9]{2}$/) }

BEGIN{
  OFS=","
  FS="[,\t]"
  while ((getline line < SAMPLES) > 0) {
    sub(/\r$/,"",line); line=trim(line)
    if (line=="") continue
    n=split(line, a, FS)
    sid=""
    c1=trim(a[1]); c2=(n>=2 ? trim(a[2]) : "")
    if (is_id(c1)) sid=canon_id(c1)
    else if (n>=2 && is_id(c2)) sid=canon_id(c2)
    if (sid=="" || sid=="SAMPLEID") continue
    samples[sid]=1
    if (is_id(c1) && n>=2 && !is_id(c2) && !is_date(c2)) sp_input[sid]=c2
    else if (is_id(c2) && !is_date(c1)) sp_input[sid]=c1
    else sp_input[sid]=""
    order[++N]=sid
  }
  close(SAMPLES)

  FS=","
  if (DBM != "" && (getline hdr < DBM) > 0) {
    while ((getline line < DBM) > 0) {
      sub(/\r$/,"",line); if (line=="") continue
      split(line, a, FS)
      proj=trim(a[1]); oid=canon_id(trim(a[2]))
      wgs=trim(a[3]); srr=trim(a[4]); sam=trim(a[5]); dat=trim(a[6])
      if (oid=="") continue
      complete=(srr!="" && srr!="NA" && sam!="" && sam!="NA")
      if (complete || !(oid in D_proj)) {
        D_proj[oid]=proj; D_wgs[oid]=wgs; D_srr[oid]=srr; D_dat[oid]=dat
      }
    }
    close(DBM)
  }

  FS="\t"
  if ((getline hdr < MASTER) <= 0) { print "ERROR: empty master TSV: " MASTER > "/dev/stderr"; exit 1 }
  sub(/\r$/,"",hdr)
  nh=split(hdr, H, FS)
  for (i=1; i<=nh; i++) mapM[H[i]]=i

  while ((getline line < MASTER) > 0) {
    sub(/\r$/,"",line); if (line=="") continue
    split(line, a, FS)
    sid_raw=(("entity:ar_pass_id" in mapM) ? a[mapM["entity:ar_pass_id"]] : "")
    sid_key=canon_id(sid_raw)
    if (sid_key=="") continue
    M_sid[sid_key]=sid_raw
    M_bsc[sid_key]=(("basespace_collection_id" in mapM) ? a[mapM["basespace_collection_id"]] : "")
    M_cdt[sid_key]=(("collection_date" in mapM) ? a[mapM["collection_date"]] : "")
    M_iso[sid_key]=(("isolation_source" in mapM) ? a[mapM["isolation_source"]] : "")
    M_spc[sid_key]=(("specimen_id" in mapM) ? a[mapM["specimen_id"]] : "")
    M_wgs[sid_key]=(("wgs_id" in mapM) ? a[mapM["wgs_id"]] : "")
    M_srr[sid_key]=(("srr_number" in mapM) ? a[mapM["srr_number"]] : "")
    M_wdt[sid_key]=(("wgs_date_put_on_sequencer" in mapM) ? a[mapM["wgs_date_put_on_sequencer"]] : "")
    M_sc[sid_key]=(("sequence_classification" in mapM) ? a[mapM["sequence_classification"]] : "")
  }
  close(MASTER)

  if (EXTRA != "") {
    if ((getline hdr2 < EXTRA) > 0) {
      sub(/\r$/,"",hdr2)
      split(hdr2, E, FS)
      for (i=1; i<=length(E); i++) mapE[E[i]]=i
      while ((getline line < EXTRA) > 0) {
        sub(/\r$/,"",line); if (line=="") continue
        split(line, b, FS)
        esid_raw=(("specimen_id" in mapE) ? b[mapE["specimen_id"]] : "")
        esid_key=canon_id(esid_raw)
        if (esid_key=="") continue
        E_sid[esid_key]=esid_raw
        E_iso[esid_key]=(("isolation_source" in mapE) ? b[mapE["isolation_source"]] : "")
        E_cdt[esid_key]=(("collect_date" in mapE) ? b[mapE["collect_date"]] : "")
      }
      close(EXTRA)
    }
  }

  found=0; miss=0
  for (i=1; i<=N; i++) {
    sid=order[i]
    in_master=(sid in M_sid)
    in_extra=(sid in E_sid)

    if (!in_master && !in_extra) {
      sp=sp_input[sid]
      proj_miss=((sid in D_proj) ? D_proj[sid] : "")
      print sid "," sp "," proj_miss >> MISSFILE
      miss++
      continue
    }

    sid_out=(in_master ? M_sid[sid] : E_sid[sid])
    spc=(in_master ? M_spc[sid] : E_sid[sid])
    sc=(in_master ? M_sc[sid] : "")
    iso=(in_master ? M_iso[sid] : "")
    cdt=(in_master ? M_cdt[sid] : "")
    if ((iso=="" || iso=="NA") && (sid in E_iso)) iso=E_iso[sid]
    if ((cdt=="" || cdt=="NA") && (sid in E_cdt)) cdt=E_cdt[sid]

    bsc=((sid in D_proj) ? D_proj[sid] : (in_master ? M_bsc[sid] : ""))
    wgs=((sid in D_wgs) ? D_wgs[sid] : (in_master ? M_wgs[sid] : ""))
    srr=((sid in D_srr) ? D_srr[sid] : (in_master ? M_srr[sid] : ""))
    dat=((sid in D_dat) ? D_dat[sid] : (in_master ? M_wdt[sid] : ""))

    printf("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
      csv(sid_out), csv(bsc), csv(spc), csv(wgs), csv(srr), csv(dat), csv(sc),
      "", "", "", csv(iso), "", "", csv(cdt), "END") >> OUTFILE
    found++
  }

  print "########################################" > "/dev/stderr"
  print "total number of samples in list: " N > "/dev/stderr"
  print "total number of rows written: " found > "/dev/stderr"
  print "########################################" > "/dev/stderr"
  if (miss > 0) {
    print "Missing " miss " sample(s) -> " MISSFILE > "/dev/stderr"
  } else {
    close(MISSFILE); system("> " MISSFILE)
    print "All requested samples were found." > "/dev/stderr"
  }
}
'
}

# ── Step 1: Extract and canonicalise source sample IDs ───────────────────────

awk '
function up(s){ return toupper(s) }
function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
function trim(s){ return ltrim(rtrim(s)) }
function is_id(s){ s=up(trim(s)); return (s ~ /^[0-9]{2}AR[0-9]+(REPEAT)?([_-].*)?$/) }
function canon_id(s){ s=up(trim(s)); sub(/[_-].*/, "", s); sub(/REPEAT$/, "", s); return s }
BEGIN{ FS="[,\t]" }
{
  line=$0; gsub(/\r$/,"",line); line=trim(line)
  if (line=="" || substr(line,1,1)=="#") next
  n=split(line, a, FS)
  sid=""
  for (i=1; i<=n; i++) {
    if (is_id(a[i])) { sid=canon_id(a[i]); break }
  }
  if (sid=="" || sid=="SAMPLEID") next
  if (!(sid in seen)) { seen[sid]=1; print sid }
}
' "$SAMPLES_FILE" > "$SOURCE_IDS"

src_count=$(wc -l < "$SOURCE_IDS" | tr -d ' ')
[[ "$src_count" -gt 0 ]] || { echo "ERROR: no sample IDs found in $SAMPLES_FILE" >&2; exit 1; }

# ── Step 2: Resolve source IDs against ar_pass.tsv ───────────────────────────

awk -v IDS="$SOURCE_IDS" -v OUT="$SOURCE_RESOLVED" -v MISS="$SOURCE_MISSING" '
function up(s){ return toupper(s) }
function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
function trim(s){ return ltrim(rtrim(s)) }
function canon_id(s){ s=up(trim(s)); sub(/[_-].*/, "", s); sub(/REPEAT$/, "", s); return s }
function extract_species(sc, m){
  sc=trim(sc)
  if (match(sc, /[A-Z][a-z]+ [a-z][A-Za-z.-]+/, m)) return m[0]
  return ""
}
function first_genus(species, a, n){
  n=split(trim(species), a, /[[:space:]]+/)
  return (n>=1 ? a[1] : species)
}
BEGIN{
  FS="\t"
  while ((getline line < IDS) > 0) { line=trim(line); if (line!="") want[line]=1 }
  close(IDS)
  print "sampleID,species,projectID,species_full" > OUT
  close(MISS)
}
NR==1 {
  for (i=1; i<=NF; i++) h[$i]=i
  if (!("entity:ar_pass_id" in h) || !("sequence_classification" in h)) {
    print "ERROR: ar_pass.tsv missing required headers" > "/dev/stderr"; exit 2
  }
  next
}
{
  sid=canon_id($(h["entity:ar_pass_id"]))
  if (!(sid in want)) next
  proj=trim($(h["basespace_collection_id"]))
  sc=trim($(h["sequence_classification"]))
  full=extract_species(sc)
  genus=first_genus(full)
  if (!(sid in found)) {
    print sid "," genus "," proj "," full >> OUT
    found[sid]=1
  }
}
END{
  for (sid in want) { if (!(sid in found)) print sid >> MISS }
}
' "$AR_PASS_TSV"

# Secondary lookup in db_master for any still-missing samples
if [[ -s "$SOURCE_MISSING" && -n "$DB_MASTER_CSV" && -f "$DB_MASTER_CSV" ]]; then
  awk -F',' -v MISS="$SOURCE_MISSING" -v RESOLVED="$SOURCE_RESOLVED" \
      -v AR_PASS="$AR_PASS_TSV" '
    function up(s){ return toupper(s) }
    function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
    function canon_id(s){ s=up(trim(s)); sub(/[_-].*/, "", s); sub(/REPEAT$/, "", s); return s }
    function extract_species(sc, m){ sc=trim(sc); if (match(sc, /[A-Z][a-z]+ [a-z][A-Za-z.-]+/, m)) return m[0]; return "" }
    function first_genus(sp, a, n){ n=split(trim(sp),a,/[[:space:]]+/); return (n>=1?a[1]:sp) }
    BEGIN {
      while ((getline line < MISS) > 0) {
        line=trim(line); sub(/\r$/,"",line)
        if (line!="") miss[toupper(line)]=line
      }
      close(MISS)
      FS="\t"
      if ((getline hdr < AR_PASS) > 0) {
        split(hdr, H, FS)
        for (i=1;i<=length(H);i++) hmap[H[i]]=i
        while ((getline line < AR_PASS) > 0) {
          split(line, a, FS)
          bsc=trim((("basespace_collection_id" in hmap)?a[hmap["basespace_collection_id"]]:""))
          sc=trim((("sequence_classification" in hmap)?a[hmap["sequence_classification"]]:""))
          if (bsc!="" && sc!="") bsc_sp[bsc]=extract_species(sc)
        }
      }
      close(AR_PASS)
      FS=","
    }
    NR==1 { next }
    {
      sub(/\r$/,"",0); n=split($0, a, FS)
      proj=trim(a[1]); oid=canon_id(trim(a[2]))
      if (oid=="" || !(oid in miss)) next
      sp=""; full=""
      if (proj in bsc_sp) { full=bsc_sp[proj]; sp=first_genus(full) }
      print oid "," sp "," proj "," full >> RESOLVED
      delete miss[oid]
    }
    END {
      close(MISS); system("> " MISS)
      for (id in miss) print miss[id] >> MISS
    }
  ' "$DB_MASTER_CSV"
fi

if [[ -s "$SOURCE_MISSING" ]]; then
  echo "ERROR: source sample(s) not found in ar_pass.tsv or db_master.csv:" >&2
  cat "$SOURCE_MISSING" >&2
  echo "Add missing rows before running outbreak prep." >&2
  exit 1
fi

# ── Step 3: Determine outbreak species ───────────────────────────────────────

outbreak_species=$(awk -F',' 'NR>1 && $2!="" {print $2}' "$SOURCE_RESOLVED" | sort -u)
species_count=$(echo "$outbreak_species" | sed '/^$/d' | wc -l | tr -d ' ')
if [[ "$species_count" -ne 1 ]]; then
  echo "ERROR: source samples resolve to $species_count species (expected exactly 1):" >&2
  awk -F',' 'NR>1 {print "  " $1 " -> " $2}' "$SOURCE_RESOLVED" >&2
  exit 1
fi
outbreak_species=$(echo "$outbreak_species" | head -n 1)

# ── Step 4: Select reference samples from ar_pass.tsv (BaseSpace-accessible) ─

refs_needed=$(( TARGET_TOTAL - src_count ))
(( refs_needed < 0 )) && refs_needed=0

echo "sampleID,species,projectID,species_full" > "$REF_SELECTED"

if (( refs_needed > 0 )); then
  awk -v IDS="$SOURCE_IDS" -v OUT="$TMP_DIR/ref_candidates.csv" \
      -v TARGET_SPECIES="$outbreak_species" '
  function up(s){ return toupper(s) }
  function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
  function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
  function trim(s){ return ltrim(rtrim(s)) }
  function canon_id(s){ s=up(trim(s)); sub(/[_-].*/, "", s); sub(/REPEAT$/, "", s); return s }
  function first_genus(species, a, n){ n=split(trim(species),a,/[[:space:]]+/); return (n>=1?a[1]:species) }
  function extract_species(sc, m){ sc=trim(sc); if (match(sc,/[A-Z][a-z]+ [a-z][A-Za-z.-]+/,m)) return m[0]; return "" }
  BEGIN{
    FS="\t"
    while ((getline line < IDS) > 0) { line=trim(line); if (line!="") source[line]=1 }
    close(IDS)
    print "sampleID,species,projectID,species_full" > OUT
  }
  NR==1 { for (i=1;i<=NF;i++) h[$i]=i; next }
  {
    sid=canon_id($(h["entity:ar_pass_id"]))
    if (sid=="" || (sid in source) || (sid in seen)) next
    sc=trim($(h["sequence_classification"]))
    full=extract_species(sc)
    genus=first_genus(full)
    if (genus != TARGET_SPECIES) next
    proj=trim($(h["basespace_collection_id"]))
    if (proj=="") next
    print sid "," genus "," proj "," full >> OUT
    seen[sid]=1
  }
  ' "$AR_PASS_TSV"

  selected_refs=0
  while IFS= read -r ref_line; do
    [[ -n "$ref_line" ]] || continue
    ref_proj=$(printf '%s\n' "$ref_line" | awk -F',' '{p=$3; sub(/_AR$/,"",p); print p}')
    if project_is_accessible "$ref_proj"; then
      printf '%s\n' "$ref_line" >> "$REF_SELECTED"
      selected_refs=$(( selected_refs + 1 ))
      if (( selected_refs >= refs_needed )); then break; fi
    fi
  done < <(tail -n +2 "$TMP_DIR/ref_candidates.csv" | sort -t',' -k3,3 -k1,1)

  if (( selected_refs < refs_needed )); then
    echo "WARN: only $selected_refs accessible reference samples found for $outbreak_species (needed $refs_needed)" >&2
  fi
fi

# Build combined source + ref sample set
{
  echo "sampleID,type,species,projectID,species_full"
  awk -F',' 'NR>1 {print $1 ",source," $2 "," $3 "," $4}' "$SOURCE_RESOLVED"
  awk -F',' 'NR>1 {print $1 ",ref," $2 "," $3 "," $4}' "$REF_SELECTED"
} > "$SELECTED_ALL"

awk -F',' 'BEGIN{print "sampleID,species,projectID"} NR>1 {print $1 "," $3 "," $4}' "$SELECTED_ALL" > "$MATCHED_DB"
awk -F',' 'NR>1 && $2=="ref" {print $1}' "$SELECTED_ALL" > "$REF_SAMPLES"

total_refs=$(wc -l < "$REF_SAMPLES" | tr -d ' ')

# ── Step 5: Verify all samples (source + ref) are accessible in BaseSpace ────

check_basespace_access "$MATCHED_DB"

# ── Step 6: Build input files ─────────────────────────────────────────────────

awk -F',' 'NR>1 {print $1}' "$MATCHED_DB" > "$TMP_DIR/all_id_list.txt"
build_metadata_csv "$TMP_DIR/all_id_list.txt" "$AR_PASS_TSV" \
                   "$EXTRA_TSV" "$DB_MASTER_CSV" "$METADATA_OUT" "$MISSING_META"

# samplesheet.csv — all samples (source + refs) for arANALYZER / BaseSpace download
{
  echo "sample,fastq_1,fastq_2"
  awk -F',' 'NR>1 && $1!="" && $3!="" {
    sid=$1; proj=$3; sub(/_AR$/, "", proj)
    name=sid "-" proj
    print name "," name ".R1.fastq.gz," name ".R2.fastq.gz"
  }' "$MATCHED_DB"
} > "$OUTDIR/samplesheet.csv"

# samplesheet_gff.csv — source samples only, used to filter arANALYZER GFF output for ROARY
{
  echo "sample"
  awk -F',' 'NR>1 && $1!="" && $2=="source" && $4!="" {
    sid=$1; proj=$4; sub(/_AR$/, "", proj)
    print sid "-" proj
  }' "$SELECTED_ALL"
} > "$OUTDIR/samplesheet_gff.csv"

# labResults.csv — all samples → expected species
{
  echo "sample,results"
  awk -F',' -v species="$outbreak_species" 'NR>1 && $1!="" && $3!="" {
    sid=$1; proj=$3; sub(/_AR$/, "", proj)
    print sid "-" proj "," species
  }' "$MATCHED_DB"
} > "$OUTDIR/labResults.csv"

# Copy prepared metadata
cp "$METADATA_OUT" "$OUTDIR/${PROJECT}_metadata.csv"

# ── Step 7: Generate the single run script ────────────────────────────────────

cat > "$OUTDIR/run_OUTBREAK_ANALYZER.sh" <<EOF
#!/usr/bin/env bash
# Auto-generated by run_ob_prep.sh for project: $PROJECT
# Run the ODHL_AR_OUTBREAK single-stage pipeline.

INPUT_DIR="\$HOME/output/$PROJECT/input"

bash "$OB_WF_DIR/run_workflow.sh" \\
  -i $PROJECT \\
  -s "\$INPUT_DIR/samplesheet.csv" \\
  -g "\$INPUT_DIR/samplesheet_gff.csv" \\
  -m "\$INPUT_DIR/${PROJECT}_metadata.csv" \\
  -p "$outbreak_species" \\
  -l "\$INPUT_DIR/labResults.csv" \\
  -f "\$INPUT_DIR/ref_samples.csv" \\
  -n "-profile docker --max_memory 7.GB --max_cpus 4 --runBASESPACE TRUE"
EOF

chmod +x "$OUTDIR/run_OUTBREAK_ANALYZER.sh"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "########################################"
echo "Outbreak prep complete for: $PROJECT"
echo "  source samples : $src_count"
echo "  reference IDs  : $total_refs  (from ar_pass.tsv)"
echo "  species        : $outbreak_species"
echo "  output dir     : $OUTDIR"
echo "########################################"
echo ""
echo "Created files:"
echo "  $OUTDIR/samplesheet.csv"
echo "  $OUTDIR/samplesheet_gff.csv"
echo "  $OUTDIR/labResults.csv"
echo "  $OUTDIR/ref_samples.csv"
echo "  $OUTDIR/${PROJECT}_metadata.csv"
echo "  $OUTDIR/run_OUTBREAK_ANALYZER.sh"
echo ""

# ── Launch watchdog ────────────────────────────────────────────────────────────

WATCHDOG_START="$OB_DIR/start_pipeline_watchdog.sh"
echo "Launching pipeline watchdog for $PROJECT ..."
bash "$WATCHDOG_START" "$PROJECT"
