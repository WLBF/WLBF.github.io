#!/bin/bash
search_dir=./posts
for entry in "$search_dir"/*
do
  title=$(sed '2q;d' $entry) 
  prefix="title: "
  echo ${title/#$prefix} > tmp.md
  echo $(sed 1,5d $entry) >> tmp.md
  mv tmp.md $entry
done
