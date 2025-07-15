#!/bin/bash
for arg in "$@"; do
  case $arg in
    -h|--help)
      maiass --committhis-help
      exit 0
      ;;
    -v|--version)
      maiass --committhis-version      # Try to read version from package.json in script directory
      exit 0
      ;;

  esac
done

maiass --commits-only
