#!/bin/bash
for arg in "$@"; do
  case $arg in
    -h|--help)
      bashmaiass --committhis-help
      exit 0
      ;;
    -v|--version)
      bashmaiass --committhis-version      # Try to read version from package.json in script directory
      exit 0
      ;;

  esac
done

bashmaiass --commits-only
