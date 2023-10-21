#!/usr/bin/env python3

# bump_build_nr.py
# Bumps build version to an APP_VERSION file containing hard-coded SemVer 2.0 struct definition:
# Ido Rabin @ Sept 2022
# python3

from typing import List, Tuple, Optional
import fileinput
from subprocess import check_output
import re
import sys
import os
import fileinput
import argparse
from tempfile import NamedTemporaryFile

# globals
FILEPATH: str = '/../Version.swift'
regex: re.Pattern = r'\b.{0,40}BUILD_NR\s{0,2}:\s{0,2}Int\s{0,2}=\s{0,2}(?P<version_int>\d+)\b'
print('= bump_build_nr.py is starting: =')
regex_key = 'version_int'

def incrementLastInt(line: str, addInt: int) -> str:
    global regex
    global regex_key

    # will either return the same line it recieved, or change the line if it contains the contains string, looking for an int to increase by addInt amount
    result: str = line
    # match with the regex:
    match = re.search(regex, result)
    if match:
        dict = match.groupdict()
        for key in dict:
            if key == regex_key:
                span = match.span(key)
                value = int(match.group(key))
                prev = result.strip()
                start: int = int(span[0])
                end: int = int(span[1])
                if value > 0 and value < 6535600:
                    new_value = value + addInt
                    # Replace at span:
                    result = result[:start] + f'{new_value}' + result[end:]
                    print(f'    Found and bumped build nr from: {value} to: {new_value}')
    return result


def processfile(filepath: str):
    # open Version file
    
    temp_file_name = ''
    with open(filepath, mode='r+', encoding='utf-8') as f:
        with NamedTemporaryFile(delete=False, mode='w+', encoding='utf-8') as fout:
            temp_file_name = fout.name
            for aline in f:
                newline = incrementLastInt(aline, +1)
                fout.write(newline)

    os.rename(temp_file_name, filepath)
    print(f'✅  {filepath} was successfully updated')

# main run:
if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        prog='Bump',
        description='Bumps build number or version by finding files with lines where the apps\' version appears using regexes, and bumping the version. Saves a valid version in all the needed locations. User may explicitly specify the root dir for the search (-p / -path arguments) or we are assuming the search should start one folder above the "current" run folder',
        epilog='Thanks')
    
    parser.add_argument('-b', '--base_folder', required=False, default='', type=str, help='The base - root folder to start the search')
    
    args = parser.parse_args()
    path = FILEPATH
    if args.base_folder is not None and len(args.base_folder) > 0:
        print(f'== base path argument: {path}')
        path = args.base_folder
    if os.path.isfile(path):
        processfile(path)
    else:
        print(f'❌ bump_build_nr.py failed finding path - please correct the path: {path}')

# TODO:
# git tag 1.2.3
# git push --tags
