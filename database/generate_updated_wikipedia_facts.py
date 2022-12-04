#!/usr/bin/env python3
# coding: utf-8

"""
Generates an updated Wikipedia facts JSON file.
"""

from __future__ import print_function

import os
import json
import sqlite3
import sys
# Validate input arguments.
if len(sys.argv) < 2:
  print('[ERROR] Not enough arguments provided!')
  print('[INFO] Usage: {0} <sdow_database> <facts_file>'.format(sys.argv[0]))
  sys.exit()

sdow_database = sys.argv[1]
facts_file = sys.argv[2]

def with_commas(val):
  """Formats the provided number with commas if it is has more than four digits."""
  return '{:,}'.format(int(val))


def get_percent_of_pages(val, decimal_places_count=2):
  """Returns the percentage di tutte le pagine the provided value represents."""
  return round(float(val) / float(query_results["non_redirect_pages_count"]) * 100, decimal_places_count)


if not os.path.isfile(sdow_database):
  raise IOError('Specified SQLite file "{0}" does not exist.'.format(sdow_database))

conn = sqlite3.connect(sdow_database)
cursor = conn.cursor()
cursor.arraysize = 1000

queries = {
    'non_redirect_pages_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0;
  ''',
    'links_count': '''
    SELECT SUM(outgoing_links_count)
    FROM links;
  ''',
    'redirects_count': '''
    SELECT COUNT(*)
    FROM redirects;
  ''',
    'pages_with_most_outgoing_links': '''
    SELECT title, outgoing_links_count
    FROM links
    INNER JOIN pages ON links.id = pages.id
    ORDER BY links.outgoing_links_count DESC
    LIMIT 5;
  ''',
    'pages_with_most_incoming_links': '''
    SELECT title, incoming_links_count
    FROM links
    INNER JOIN pages ON links.id = pages.id
    ORDER BY links.incoming_links_count DESC
    LIMIT 5;
  ''',
    'first_article_sorted_alphabetically': '''
    SELECT title
    FROM pages
    WHERE is_redirect = 0
    ORDER BY title ASC
    LIMIT 1;
  ''',
    'last_article_sorted_alphabetically': '''
    SELECT title
    FROM pages
    WHERE is_redirect = 0
    ORDER BY title DESC
    LIMIT 1;
  ''',
    'pages_with_no_incoming_or_outgoing_links_count': '''
    SELECT COUNT(*)
    FROM pages
    LEFT JOIN links ON pages.id = links.id
    WHERE is_redirect = 0
      AND links.id IS NULL;
  ''',
    'pages_with_no_outgoing_links_count': '''
    SELECT COUNT(*)
    FROM links
    WHERE outgoing_links_count = 0;
  ''',
    'pages_with_no_incoming_links_count': '''
    SELECT COUNT(*)
    FROM links
    WHERE incoming_links_count = 0;
  ''',
    'longest_page_title': '''
    SELECT title
    FROM pages
    WHERE is_redirect = 0
    ORDER BY LENGTH(title) DESC
    LIMIT 1;
  ''',
    'longest_page_titles_with_no_spaces': '''
    SELECT title
    FROM pages
    WHERE is_redirect = 0
      AND INSTR(title, '_') = 0
    ORDER BY LENGTH(title) DESC
    LIMIT 3;
  ''',
    'pages_with_single_character_title': '''
    SELECT title
    FROM pages
    WHERE is_redirect = 0
      AND LENGTH(title) = 1
    ORDER BY title DESC;
  ''',
    'pages_with_single_character_title_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND LENGTH(title) = 1;
  ''',
    'page_titles_starting_with_exclamation_mark_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND title LIKE '!%';
  ''',
    'page_titles_containing_exclamation_mark_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND INSTR(title, '!') > 0;
  ''',
    'page_titles_starting_with_question_mark_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND title LIKE '?%';
  ''',
    'page_titles_containing_question_mark_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND INSTR(title, '?') > 0;
  ''',
    'page_titles_containing_spaces_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND INSTR(title, '_') > 0;
  ''',
    'page_titles_containing_no_spaces_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND INSTR(title, '_') = 0;
  ''',
    'page_titles_containing_quotation_mark_count': '''
    SELECT COUNT(*)
    FROM pages
    WHERE is_redirect = 0
      AND (INSTR(title, '"') > 0
           OR INSTR(title, "'") > 0);
  ''',
}

# Execute and store the result of each query.
query_results = {}
for key, query in queries.items():
  cursor.execute(query)

  current_query_results = []
  for i, result in enumerate(cursor.fetchall()):
    tokens = []
    for token in result:
      if not isinstance(token, int):
        token = token.replace('_', ' ').replace('\\', '')
      tokens.append(token)

    if (len(tokens) == 1):
      current_query_results.append(tokens[0])
    else:
      current_query_results.append(tokens)

  query_results[key] = current_query_results[0] if len(
      current_query_results) == 1 else current_query_results

facts = [
    "Wikipedia contiene {0} pagine.".format(with_commas(query_results["non_redirect_pages_count"])),
    "Ci sono un totale di {0} link tra pagine di Wikipedia.".format(
        with_commas(query_results["links_count"])),
    "{0} pagine di Wikipedia sono solo redirect ad altre pagine.".format(
        with_commas(query_results["redirects_count"])),

    "La prima pagina di Wikipedia in ordine alfabetico è \"{0}\".".format(
        query_results["first_article_sorted_alphabetically"]),
    "L'ultima pagina di Wikipedia in ordine alfabetico è  \"{0}\".".format(
        query_results["last_article_sorted_alphabetically"]),

    "{0} pagine di Wikipedia ({1}% di tutte le pagine) non hanno link in ingresso o uscita.".format(with_commas(
        query_results["pages_with_no_incoming_or_outgoing_links_count"]), get_percent_of_pages(query_results["pages_with_no_incoming_or_outgoing_links_count"], 3)),
    "Ci sono {0} pagine di Wikipedia ({1}% di tutte le pagine) che non hanno link ad altre pagine.".format(with_commas(
        query_results["pages_with_no_outgoing_links_count"] + query_results["pages_with_no_incoming_or_outgoing_links_count"]), get_percent_of_pages(query_results["pages_with_no_outgoing_links_count"] + query_results["pages_with_no_incoming_or_outgoing_links_count"])),
    "Ci sono {0} pagine di Wikipedia ({1}% di tutte le pagine) che non sono linkate da altre pagine.".format(with_commas(
        query_results["pages_with_no_incoming_links_count"] + query_results["pages_with_no_incoming_or_outgoing_links_count"]), get_percent_of_pages(query_results["pages_with_no_incoming_links_count"] + query_results["pages_with_no_incoming_or_outgoing_links_count"])),

    "Con l'impressionante lunghezza di {0} caratteri, \"{1}\" è la pagina di Wikipedia col titolo più lungo".format(len(query_results["longest_page_title"]),
                                                                                           query_results["longest_page_title"]),
    "Ci sono {0} pagine di Wikipedia ({1}% di tutte le pagine) i cui titoli sono di un singolo carattere, tra cui \"{2}\", \"{3}\" e \"{4}\".".format(
        query_results["pages_with_single_character_title_count"], get_percent_of_pages(query_results["pages_with_single_character_title_count"], 3), 
        query_results["pages_with_single_character_title"][2], query_results["pages_with_single_character_title"][3], query_results["pages_with_single_character_title"][4]),

    "Solo {0} pagine di Wikipedia cominciano con un punto esclamativo.".format(
        with_commas(query_results["page_titles_starting_with_exclamation_mark_count"])),
    "{0} pagine di Wikipedia ({1}%) hanno un titolo che contiene un punto esclamativo.".format(with_commas(
        query_results["page_titles_containing_exclamation_mark_count"]), get_percent_of_pages(query_results["page_titles_containing_exclamation_mark_count"])),

    "Solo {0} pagine di Wikipedia cominciano con un punto interrogativo.".format(
        with_commas(query_results["page_titles_starting_with_question_mark_count"])),
    "{0} pagine di Wikipedia ({1}%) hanno un titolo che contiene un punto esclamativo.".format(with_commas(
        query_results["page_titles_containing_question_mark_count"]), get_percent_of_pages(query_results["page_titles_containing_question_mark_count"])),

    "{0} pagine di Wikipedia ({1}%) hanno un titolo che contiene uno spazio.".format(with_commas(
        query_results["page_titles_containing_spaces_count"]), get_percent_of_pages(query_results["page_titles_containing_spaces_count"], 1)),
    "{0} pagine di Wikipedia ({1}%) hanno un titolo che non cintiene spazi.".format(with_commas(
        query_results["page_titles_containing_no_spaces_count"]), get_percent_of_pages(query_results["page_titles_containing_no_spaces_count"], 1)),

    "Apici o virgolette si trovano nel titolo di {0} pagine di Wikipedia ({1}% di tutte le pagine), causando innumerevoli problemi di analisi durante la creazione di questo sito.".format(
        with_commas(query_results["page_titles_containing_quotation_mark_count"]), get_percent_of_pages(query_results["page_titles_containing_quotation_mark_count"])),

    "Con ben {0} caratteri, \"{1}\" è la pagina di Wikipedia col titolo più lungo che non contiene spazi.".format(
        len(query_results["longest_page_titles_with_no_spaces"][0]), query_results["longest_page_titles_with_no_spaces"][0]),
    "Con {0} caratteri, \"{1}\" è la pagina di Wikipedia col secondo titolo più lungo che non contiene spazi".format(
        len(query_results["longest_page_titles_with_no_spaces"][1]), query_results["longest_page_titles_with_no_spaces"][1]),
    "Con {0} caratteri, \"{1}\" è la pagina di Wikipedia col terzo titolo più lungo che non contiene spazi".format(
        len(query_results["longest_page_titles_with_no_spaces"][2]), query_results["longest_page_titles_with_no_spaces"][2])

]

ordinals = ['', 'seconda ', 'terza ', 'quarta ', 'quinta ']

for i, (title, outgoing_links_count) in enumerate(query_results["pages_with_most_outgoing_links"]):
  facts.append("\"{0}\" è la pagina di Wikipedia con il {1}più alto numero di link in uscita ({2}).".format(
      title, ordinals[i], with_commas(outgoing_links_count)))

for i, (title, incoming_links_count) in enumerate(query_results["pages_with_most_incoming_links"]):
  facts.append("\"{0}\" è la {1}pagina più linkata di Wikipedia ({2} link entranti).".format(
      title, ordinals[i], with_commas(incoming_links_count)))

with open(facts_file, 'w', encoding='utf-8') as f:
    json.dump(facts, f, ensure_ascii=False, indent=2)

# print(json.dumps(facts, indent=2, ensure_ascii=False))
