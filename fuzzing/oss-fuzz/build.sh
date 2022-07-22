#!/bin/bash -eu
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

# setup Qt source folder
SOURCES="$SRC/qt"
if [ ! -d "$SOURCES" ]; then
    SOURCES=$SRC
fi

# build qtbase
mkdir -p $WORK/qt
cd $WORK/qt

$SOURCES/qtbase/configure -opensource -confirm-license -prefix $PWD \
                          -platform linux-clang-libc++ -release -static \
                          -qt-libmd4c -no-opengl -no-widgets -- \
                          -DCMAKE_CXX_FLAGS_RELEASE="-O1" -DQT_USE_DEFAULT_CMAKE_OPTIMIZATION_FLAGS=ON
VERBOSE=1 cmake --build . --parallel

# build additional modules
for module in qtimageformats \
              qtsvg
do
    buildDir="$WORK/build-$module"
    mkdir -p $buildDir
    pushd $buildDir
    $WORK/qt/bin/qt-cmake -S "$SOURCES/$module" -GNinja
    VERBOSE=1 cmake --build . --parallel
    popd
done

# prepare corpus files
testcasesPath="$SOURCES/qtqa/fuzzing/testcases"
zip -j $WORK/cbor $testcasesPath/cbor/*
zip -j $WORK/datetime $testcasesPath/datetime/*
zip -j $WORK/html $testcasesPath/html/*
zip -j $WORK/icc $testcasesPath/icc/*
zip -j $WORK/images $testcasesPath/{bmp,gif,icns,ico,jpg,png,svg,xbm,xpm}/* $SRC/afltestcases/images/*/*
zip -j $WORK/json $testcasesPath/json/*
zip -j $WORK/markdown $testcasesPath/markdown/*
zip -j $WORK/regexp.zip $testcasesPath/regexp/*
zip -j $WORK/ssl.pem.zip $testcasesPath/ssl.pem/*
zip -j $WORK/svg $testcasesPath/svg/*
zip -j $WORK/text $testcasesPath/text/* $SRC/afltestcases/others/text/*
zip -j $WORK/xml $testcasesPath/xml/* $SRC/afltestcases/others/xml/*

# prepare merged dictionaries
mergedDictsPath="$WORK/merged_dicts"
mkdir -p $mergedDictsPath
cat $SRC/afldictionaries/{css,html_tags}.dict > "$mergedDictsPath/css_and_html.dict"
cat $SRC/afldictionaries/{bmp,dds,exif,gif,icns,jpeg,png,svg,tiff,webp}.dict > "$mergedDictsPath/images.dict"

# build fuzzers

build_fuzzer() {
    local module=$1
    local srcDir="$2"
    local format=${3-""}
    local dictionary=${4-""}
    local exeName="${srcDir##*/}"
    local targetName="${module}_${srcDir//\//_}"
    local buildFolder="build_$targetName"
    mkdir -p $buildFolder
    pushd $buildFolder
    $WORK/qt/bin/qt-cmake -S "$SOURCES/$module/tests/libfuzzer/$srcDir" -GNinja
    VERBOSE=1 cmake --build . --parallel

    mv "$exeName" "$OUT/$targetName"
    if [ -n "$format" ]; then
        cp "$WORK/$format.zip" "$OUT/${targetName}_seed_corpus.zip"
    fi
    if [ -n "$dictionary" ]; then
        cp "$dictionary" "$OUT/$targetName.dict"
    fi
    popd
    rm -r $buildFolder
}

build_fuzzer "qtbase" "corelib/serialization/qcborstreamreader/next" "cbor"
build_fuzzer "qtbase" "corelib/serialization/qcborvalue/fromcbor" "cbor"
build_fuzzer "qtbase" "corelib/serialization/qjsondocument/fromjson" "json" "$SRC/afldictionaries/json.dict"
build_fuzzer "qtbase" "corelib/serialization/qtextstream/extractionoperator-float" "text"
build_fuzzer "qtbase" "corelib/serialization/qxmlstream/qxmlstreamreader/readnext" "xml" "$SRC/afldictionaries/xml.dict"
build_fuzzer "qtbase" "corelib/text/qregularexpression/optimize" "regexp" "$SRC/afldictionaries/regexp.dict"
build_fuzzer "qtbase" "corelib/time/qdatetime/fromstring" "datetime"
build_fuzzer "qtbase" "corelib/tools/qcryptographichash/result"
build_fuzzer "qtbase" "gui/image/qimage/loadfromdata" "images" "$WORK/merged_dicts/images.dict"
build_fuzzer "qtbase" "gui/painting/qcolorspace/fromiccprofile" "icc" "$SRC/afldictionaries/iccprofile.dict"
build_fuzzer "qtbase" "gui/text/qtextdocument/sethtml" "html" "$WORK/merged_dicts/css_and_html.dict"
build_fuzzer "qtbase" "gui/text/qtextdocument/setmarkdown" "markdown" "$SRC/afldictionaries/markdown.dict"
build_fuzzer "qtbase" "gui/text/qtextlayout/beginlayout" "text"
build_fuzzer "qtbase" "network/ssl/qsslcertificate/qsslcertificate/pem" "ssl.pem"
build_fuzzer "qtsvg" "svg/qsvgrenderer/render" "svg" "$SRC/afldictionaries/svg.dict"

rm -r "$WORK/merged_dicts"
