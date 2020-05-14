# special case skip regeneration
# scripts.pro and children projects are not ported yet.
# If the need arises, it can be done.
# The empty file exists only for the purpose of mimicking the
# Coin qmake instructins, where qmake is executed directly on the
# scripts.pro folder. Hence the same should be possible for CMake.
cmake_minimum_required(VERSION 3.15)
project(QtQualityAssuranceScripts)
