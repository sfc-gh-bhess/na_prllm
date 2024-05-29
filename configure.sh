#!/bin/bash

# Prompt user for input
read -p "What is the image repository URL (SHOW IMAGE REPOSITORIES IN SCHEMA)? " repository_url
read -p "What is your HuggingFace token? " hf_token
read -p "What is the database for your models stage? " database
read -p "What is the schema for your models stage? " schema

# Paths to the files
makefile="./Makefile"
llm_yaml="./llm.yaml"

# Copy files
cp $makefile.template $makefile
cp $llm_yaml.template $llm_yaml

# Replace placeholders in Makefile file using | as delimiter
sed -i "" "s|<<repository_url>>|$repository_url|g" $makefile
sed -i "" "s|<<repository_url>>|$repository_url|g" $llm_yaml
sed -i "" "s|<<hf_token>>|$ht_token|g" $llm_yaml
sed -i "" "s|<<database>>|$database|g" $llm_yaml
sed -i "" "s|<<schema>>|$schema|g" $llm_yaml


echo "Placeholder values have been replaced!"
