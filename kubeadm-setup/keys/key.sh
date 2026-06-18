#!/usr/bin/env bash 

read -p "Enter the name of the key pair [terraform-key]: " key_name

key_name=${key_name:-terraform-key}

ssh-keygen -t rsa -b 4096 -C "$key_name" -f "$key_name.pem" -N ""

chmod 400 "$key_name.pem"
