#!/bin/bash
for arg in "$@"; do
  case $arg in
    -h|--help)
      maiass --aicommit-help
      exit 0
      ;;
  esac
done

maiass --commits-only
