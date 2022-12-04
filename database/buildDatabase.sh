#!/bin/bash

set -uo pipefail

# Force default language for output sorting to be bytewise. Necessary to ensure uniformity amongst
# UNIX commands.
export LC_ALL=C

DOWNLOAD_SERVER="https://ftp.acc.umu.se/mirror/wikimedia.org/dumps"

if [[ $# -le 0 ]]; then
  WIKI_LANG="it"
else
  WIKI_LANG=$1
fi
WIKI=${WIKI_LANG}wiki

# By default, the latest Wikipedia dump will be downloaded. If a download date in the format
# YYYYMMDD is provided as the first argument, it will be used instead.
if [[ $# -le 1 ]]; then
  DOWNLOAD_DATE=$(wget -q -O- $DOWNLOAD_SERVER/$WIKI/ | grep -Po '\d{8}' | sort | tail -n1)
else
  if [ ${#2} -ne 8 ]; then
    echo "[ERROR] Invalid download date provided: $1"
    exit 1
  else
    DOWNLOAD_DATE=$2
  fi
fi


ROOT_DIR=`pwd`
OUT_DIR="dump"

DOWNLOAD_URL="$DOWNLOAD_SERVER/$WIKI/$DOWNLOAD_DATE"

SHA1SUM_FILENAME="$WIKI-$DOWNLOAD_DATE-sha1sums.txt"
REDIRECTS_FILENAME="$WIKI-$DOWNLOAD_DATE-redirect.sql.gz"
PAGES_FILENAME="$WIKI-$DOWNLOAD_DATE-page.sql.gz"
LINKS_FILENAME="$WIKI-$DOWNLOAD_DATE-pagelinks.sql.gz"


# Make the output directory if it doesn't already exist and move to it
mkdir -p $OUT_DIR
pushd $OUT_DIR > /dev/null


echo "[INFO] Download date: $DOWNLOAD_DATE"
echo "[INFO] Download URL: $DOWNLOAD_URL"
echo "[INFO] Output directory: $OUT_DIR"
echo

##############################
#  DOWNLOAD WIKIPEDIA DUMPS  #
##############################

if [ -f "sdow-$WIKI-$DOWNLOAD_DATE.sqlite.gz" ]; then
    echo "[WARN] Already created SQLite database"
    exit 1
fi


function download_file() {
  if [ ! -f $2 ]; then
    echo
    echo "[INFO] Downloading $1 file via wget"
    time wget --continue --no-use-server-timestamps --progress=dot:giga -O "$2.tmp" "$DOWNLOAD_URL/$2"
    mv "$2.tmp" "$2"
  else
    echo "[WARN] Already downloaded $1 file"
  fi

  if [ $1 != sha1sums ]; then
    echo
    echo "[INFO] Verifying SHA-1 hash for $1 file"
    # time grep "$2" "$SHA1SUM_FILENAME" | sha1sum -c
    if [ $? -ne 0 ]; then
      echo "[ERROR] Downloaded $1 file has incorrect SHA-1 hash"
      # rm $2
      exit 1
    fi
  fi
}

download_file "sha1sums" $SHA1SUM_FILENAME
download_file "redirects" $REDIRECTS_FILENAME
download_file "pages" $PAGES_FILENAME
download_file "links" $LINKS_FILENAME

##########################
#  TRIM WIKIPEDIA DUMPS  #
##########################
if [ ! -f redirects.txt.gz ]; then
  echo
  echo "[INFO] Trimming redirects file"

  # Unzip
  # Remove all lines that don't start with INSERT INTO...
  # Split into individual records
  # Only keep records in namespace 0
  # Replace namespace with a tab
  # Remove everything starting at the to page name's closing apostrophe
  # Zip into output file
  time pigz -dc $REDIRECTS_FILENAME \
    | sed -n 's/^INSERT INTO `redirect` VALUES (//p' \
    | sed -e 's/),(/\'$'\n/g' \
    | egrep "^[0-9]+,0," \
    | sed -e $"s/,0,'/\t/g" \
    | sed -e "s/','.*//g" \
    | pigz --fast > redirects.txt.gz.tmp
  mv redirects.txt.gz.tmp redirects.txt.gz
else
  echo "[WARN] Already trimmed redirects file"
fi

if [ ! -f pages.txt.gz ]; then
  echo
  echo "[INFO] Trimming pages file"

  # Unzip
  # Remove all lines that don't start with INSERT INTO...
  # Split into individual records
  # Only keep records in namespace 0
  # Replace namespace with a tab
  # Splice out the page title and whether or not the page is a redirect
  # Zip into output file
  time pigz -dc $PAGES_FILENAME \
    | sed -n 's/^INSERT INTO `page` VALUES (//p' \
    | sed -e 's/),(/\'$'\n/g' \
    | egrep "^[0-9]+,0," \
    | sed -e $"s/,0,'/\t/" \
    | sed -e $"s/',*,\([01]\).*/\t\1/" \
    | pigz --fast > pages.txt.gz.tmp
  mv pages.txt.gz.tmp pages.txt.gz
else
  echo "[WARN] Already trimmed pages file"
fi

if [ ! -f links.txt.gz ]; then
  echo
  echo "[INFO] Trimming links file"

  # Unzip
  # Remove all lines that don't start with INSERT INTO...
  # Split into individual records
  # Only keep records in namespace 0
  # Replace namespace with a tab
  # Remove everything starting at the to page name's closing apostrophe
  # Zip into output file
  time pigz -dc $LINKS_FILENAME \
    | sed -n 's/^INSERT INTO `pagelinks` VALUES (//p' \
    | sed -e 's/),(/\'$'\n/g' \
    | egrep "^[0-9]+,0,.*,0$" \
    | sed -e $"s/,0,'/\t/g" \
    | sed -e "s/',0//g" \
    | pigz --fast > links.txt.gz.tmp
  mv links.txt.gz.tmp links.txt.gz
else
  echo "[WARN] Already trimmed links file"
fi


###########################################
#  REPLACE TITLES AND REDIRECTS IN FILES  #
###########################################
if [ ! -f redirects.with_ids.txt.gz ]; then
  echo
  echo "[INFO] Replacing titles in redirects file"
  time python3 "$ROOT_DIR/replace_titles_in_redirects_file.py" pages.txt.gz redirects.txt.gz \
    | sort -S 100% -t $'\t' -k 1n,1n \
    | pigz --fast > redirects.with_ids.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of redirects.with_ids.txt.gz failed"
    exit 1
  fi
  mv redirects.with_ids.txt.gz.tmp redirects.with_ids.txt.gz
else
  echo "[WARN] Already replaced titles in redirects file"
fi

if [ ! -f links.with_ids.txt.gz ]; then
  echo
  echo "[INFO] Replacing titles and redirects in links file"
  time python3 "$ROOT_DIR/replace_titles_and_redirects_in_links_file.py" pages.txt.gz redirects.with_ids.txt.gz links.txt.gz \
    | pigz --fast > links.with_ids.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.with_ids.txt.gz failed"
    exit 1
  fi
  mv links.with_ids.txt.gz.tmp links.with_ids.txt.gz
else
  echo "[WARN] Already replaced titles and redirects in links file"
fi

if [ ! -f pages.pruned.txt.gz ]; then
  echo
  echo "[INFO] Pruning pages which are marked as redirects but with no redirect"
  time python3 "$ROOT_DIR/prune_pages_file.py" pages.txt.gz redirects.with_ids.txt.gz \
    | pigz --fast > pages.pruned.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of pages.pruned.txt.gz failed"
    exit 1
  fi
  mv pages.pruned.txt.gz.tmp pages.pruned.txt.gz
else
  echo "[WARN] Already pruned pages which are marked as redirects but with no redirect"
fi

#####################
#  SORT LINKS FILE  #
#####################
if [ ! -f links.sorted_by_source_id.txt.gz ]; then
  echo
  echo "[INFO] Sorting links file by source page ID"
  time pigz -dc links.with_ids.txt.gz \
    | sort -S 80% -t $'\t' -k 1n,1n \
    | uniq \
    | pigz --fast > links.sorted_by_source_id.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.sorted_by_source_id.txt.gz failed"
    exit 1
  fi
  mv links.sorted_by_source_id.txt.gz.tmp links.sorted_by_source_id.txt.gz
else
  echo "[WARN] Already sorted links file by source page ID"
fi

if [ ! -f links.sorted_by_target_id.txt.gz ]; then
  echo
  echo "[INFO] Sorting links file by target page ID"
  time pigz -dc links.with_ids.txt.gz \
    | sort -S 80% -t $'\t' -k 2n,2n \
    | uniq \
    | pigz --fast > links.sorted_by_target_id.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.sorted_by_target_id.txt.gz failed"
    exit 1
  fi
  mv links.sorted_by_target_id.txt.gz.tmp links.sorted_by_target_id.txt.gz
else
  echo "[WARN] Already sorted links file by target page ID"
fi


#############################
#  GROUP SORTED LINKS FILE  #
#############################
if [ ! -f links.grouped_by_source_id.txt.gz ]; then
  echo
  echo "[INFO] Grouping source links file by source page ID"
  time pigz -dc links.sorted_by_source_id.txt.gz \
   | awk -F '\t' '$1==last {printf "|%s",$2; next} NR>1 {print "";} {last=$1; printf "%s\t%s",$1,$2;} END{print "";}' \
   | pigz --fast > links.grouped_by_source_id.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.grouped_by_source_id.txt.gz failed"
    exit 1
  fi
  mv links.grouped_by_source_id.txt.gz.tmp links.grouped_by_source_id.txt.gz
else
  echo "[WARN] Already grouped source links file by source page ID"
fi

if [ ! -f links.grouped_by_target_id.txt.gz ]; then
  echo
  echo "[INFO] Grouping target links file by target page ID"
  time pigz -dc links.sorted_by_target_id.txt.gz \
    | awk -F '\t' '$2==last {printf "|%s",$1; next} NR>1 {print "";} {last=$2; printf "%s\t%s",$2,$1;} END{print "";}' \
    | pigz --fast > links.grouped_by_target_id.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.grouped_by_target_id.txt.gz failed"
    exit 1
  fi
  mv links.grouped_by_target_id.txt.gz.tmp links.grouped_by_target_id.txt.gz
else
  echo "[WARN] Already grouped target links file by target page ID"
fi


################################
# COMBINE GROUPED LINKS FILES  #
################################
if [ ! -f links.with_counts.txt.gz ]; then
  echo
  echo "[INFO] Combining grouped links files"
  time python3 "$ROOT_DIR/combine_grouped_links_files.py" links.grouped_by_source_id.txt.gz links.grouped_by_target_id.txt.gz \
    | pigz --fast > links.with_counts.txt.gz.tmp
  if [ $? -ne 0 ]; then
    echo "[ERROR] Creation of links.with_counts.txt.gz failed"
    exit 1
  fi
  mv links.with_counts.txt.gz.tmp links.with_counts.txt.gz
else
  echo "[WARN] Already combined grouped links files"
fi


############################
#  CREATE SQLITE DATABASE  #
############################
if [ ! -f sdow.sqlite ]; then
  echo
  echo "[INFO] Creating redirects table"
  time pigz -dc redirects.with_ids.txt.gz | sqlite3 sdow.sqlite ".read $ROOT_DIR/sql/createRedirectsTable.sql"

  echo
  echo "[INFO] Creating pages table"
  time pigz -dc pages.pruned.txt.gz | sqlite3 sdow.sqlite ".read $ROOT_DIR/sql/createPagesTable.sql"

  echo
  echo "[INFO] Creating links table"
  time pigz -dc links.with_counts.txt.gz | sqlite3 sdow.sqlite ".read $ROOT_DIR/sql/createLinksTable.sql"

  echo
  echo "[INFO] Deleting files"
  rm -f redirects.txt.gz
  rm -f pages.txt.gz
  rm -f links.txt.gz
  rm -f redirects.with_ids.txt.gz
  rm -f links.with_ids.txt.gz
  rm -f pages.pruned.txt.gz
  rm -f links.sorted_by_source_id.txt.gz
  rm -f links.sorted_by_target_id.txt.gz
  rm -f links.grouped_by_source_id.txt.gz
  rm -f links.grouped_by_target_id.txt.gz
  rm -f links.with_counts.txt.gz
  rm -f $SHA1SUM_FILENAME
  rm -f $REDIRECTS_FILENAME
  rm -f $PAGES_FILENAME
  rm -f $LINKS_FILENAME

else
  echo "[WARN] Already created SQLite database"
fi

python3 "$ROOT_DIR/generate_updated_wikipedia_facts.py" sdow.sqlite "wikipediaFacts-$WIKI-$DOWNLOAD_DATE.json"

echo
echo "[INFO] Compressing SQLite file"
time pigz --best --keep --stdout sdow.sqlite > "sdow-$WIKI-$DOWNLOAD_DATE.sqlite.gz.tmp"
if [ $? -ne 0 ]; then
  echo "[ERROR] Creation of sdow-$WIKI-$DOWNLOAD_DATE.sqlite.gz failed"
  exit 1
fi
mv "sdow-$WIKI-$DOWNLOAD_DATE.sqlite.gz.tmp" "sdow-$WIKI-$DOWNLOAD_DATE.sqlite.gz"

echo
echo "[INFO] Deleting DB"
rm -f sdow.sqlite

echo
echo "[INFO] All done!"
