#!/usr/bin/env python2
# -*- coding: utf-8 -*-

# (c) Guillaume Michel
# https://github.com/guillaumemichel/icao-nnumber_converter
# Licensed under Gnu Public License GPLv3.

import sys
from math import pow

ICAO_SIZE = 6           # size of an icao address
NNUMBER_MAX_SIZE = 6    # max size of a N-Number

charset = "ABCDEFGHJKLMNPQRSTUVWXYZ" # alphabet without I and O
digitset = "0123456789"
hexset = "0123456789ABCDEF"
allchars = charset+digitset

suffix_size = 1 + len(charset) + int(pow(len(charset),2))   # 601
bucket4_size = 1 + len(charset) + len(digitset)             # 35
bucket3_size = len(digitset)*bucket4_size + suffix_size     # 951
bucket2_size = len(digitset)*(bucket3_size) + suffix_size   # 10111
bucket1_size = len(digitset)*(bucket2_size) + suffix_size   # 101711

def get_suffix(offset):
    """
    Compute the suffix for the tail number given an offset
    offset < suffix_size
    An offset of 0 returns in a valid emtpy suffix
    A non-zero offset return a string containing one or two character from 'charset'
    Reverse function of suffix_shift()

    0 -> ''
    1 -> 'A'
    2 -> 'AA'
    3 -> 'AB'
    4 -> 'AC'
    ...
    24 -> 'AZ'
    25 -> 'B'
    26 -> 'BA'
    27 -> 'BB'
    ...
    600 -> 'ZZ'
    """
    if offset==0:
        return ''
    char0 = charset[int((offset-1)/(len(charset)+1))]
    rem = (offset-1)%(len(charset)+1)
    if rem==0:
        return char0
    return char0+charset[rem-1]

def suffix_offset(s):
    """
    Compute the offset corresponding to the given alphabetical suffix
    Reverse function of get_suffix()
    ''   -> 0
    'A'  -> 1
    'AA' -> 2
    'AB' -> 3
    'AC' -> 4
    ...
    'AZ' -> 24
    'B'  -> 25
    'BA' -> 26
    'BB' -> 27
    ...
    'ZZ' -> 600
    """
    if len(s)==0:
        return 0
    valid = True
    if len(s)>2:
        valid = False
    else:
        for c in s:
            if c not in charset:
                valid = False
                break

    if not valid:
        print("parameter of suffix_shift() invalid")
        print(s)
        return None
    
    count = (len(charset)+1)*charset.index(s[0]) + 1
    if len(s)==2:
        count += charset.index(s[1]) + 1
    return count


def create_icao(prefix, i):
    """
    Creates an american icao number composed from the prefix ('a' for USA)
    and from the given number i
    The output is an hexadecimal of length 6 starting with the suffix

    Example: create_icao('a', 11) -> "a0000b"
    """
    suffix = hex(i)[2:]
    l = len(prefix)+len(suffix)
    if l>ICAO_SIZE:
        return None
    return prefix + '0'*(ICAO_SIZE-l) + suffix

def n_to_icao(nnumber):
    """
    Convert a Tail Number (N-Number) to the corresponding ICAO address
    Only works with US registrations (ICAOS starting with 'a' and tail number starting with 'N')
    Return None for invalid parameter
    Return the ICAO address associated with the given N-Number in string format on success
    """

    # check parameter validity
    valid = True
    if (not 0<len(nnumber)<=NNUMBER_MAX_SIZE) or nnumber[0] != 'N':
        valid = False
    else:
        for c in nnumber:
            if c not in allchars:
                valid = False
                break
    if not valid:
        return None
    
    prefix = 'a'
    count = 0

    if len(nnumber) > 1:
        nnumber = nnumber[1:]
        count += 1
        for i in range(len(nnumber)):
            if i == NNUMBER_MAX_SIZE-2: # NNUMBER_MAX_SIZE-2 = 4
                # last possible char (in allchars)
                count += allchars.index(nnumber[i])+1
            elif nnumber[i] in charset:
                # first alphabetical char
                count += suffix_offset(nnumber[i:])
                break # nothing comes after alphabetical chars
            else:
                # number
                if i == 0:
                    count += (int(nnumber[i])-1)*bucket1_size
                elif i == 1:
                    count += int(nnumber[i])*bucket2_size + suffix_size
                elif i == 2:
                    count += int(nnumber[i])*bucket3_size + suffix_size
                elif i == 3:
                    count += int(nnumber[i])*bucket4_size + suffix_size
    return create_icao(prefix, count)

def icao_to_n(icao):
    """
    Convert an ICAO address to its associated tail number (N-Number)
    Only works with US registrations (ICAOS starting with 'a' and tail number starting with 'N')
    Return None for invalid parameter
    Return the tail number associated with the given ICAO in string format on success
    """

    # check parameter validity
    icao = icao.upper()
    valid = True
    if len(icao) != ICAO_SIZE or icao[0] != 'A':
        valid = False
    else:
        for c in icao:
            if c not in hexset:
                valid = False
                break
    
    # return None for invalid parameter
    if not valid:
        return None

    output = 'N' # digit 0 = N

    i = int(icao[1:], base=16)-1 # parse icao to int
    if i < 0:
        return output

    dig1 = int(i/bucket1_size) + 1 # digit 1
    rem1 = i%bucket1_size
    output += str(dig1)

    if rem1 < suffix_size:
        return output + get_suffix(rem1)

    rem1 -= suffix_size # shift for digit 2
    dig2 = int(rem1/bucket2_size)
    rem2 = rem1%bucket2_size
    output += str(dig2)

    if rem2 < suffix_size:
        return output + get_suffix(rem2)

    rem2 -= suffix_size # shift for digit 3
    dig3 = int(rem2/bucket3_size)
    rem3 = rem2%bucket3_size
    output += str(dig3)

    if rem3 < suffix_size:
        return output + get_suffix(rem3)

    rem3 -= suffix_size # shift for digit 4
    dig4 = int(rem3/bucket4_size)
    rem4 = rem3%bucket4_size
    output += str(dig4)

    if rem4 == 0:
        return output

    # find last character
    return output + allchars[rem4-1]

def print_help():
    print('Usage: python '+sys.argv[0]+' [icao / nnumber]')
    print()
    print('Convert an ICAO address to a N-Number (Tail Number) and reciprocally')
    print('Only works for aircrafts registered in the United States')
    print("US N-Numbers are alphanumerical, start with 'N', and are at most 6 character long")
    print("US ICAO addresses are hexideciaml, start with 'a', and are at most 6 character long")
    print()
    print('Examples:\n  python '+sys.argv[0]+' N123AB\n  python '+sys.argv[0]+' abcdef')
    sys.exit()

def invalid_parameter():
    print("> Invalid parameter\nN-Number should be in range N1-N99999\nICAO address should be in range a00001-adf7c7")
    sys.exit()

if __name__ == "__main__":
    if len(sys.argv)-1 != 1:
        print_help()

    val = sys.argv[1].upper()

    if val in ['H', '-H', 'HELP', '-HELP', '--HELP']:
        print_help()
    
    if val[0] == 'N': # N-Number
        res = n_to_icao(val)
    elif val[0] == 'A': # icao
        res = icao_to_n(val)
    else:
        invalid_parameter()

    if res is None:
        invalid_parameter()
    print(res)
