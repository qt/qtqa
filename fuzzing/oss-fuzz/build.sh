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

# add the flags to Qt build, gratefully borrowed from karchive
cd $SRC/qt/qtbase/mkspecs
sed -i -e "s/QMAKE_CXXFLAGS    += -stdlib=libc++/QMAKE_CXXFLAGS    += -stdlib=libc++  $CXXFLAGS\nQMAKE_CFLAGS += $CFLAGS/g" linux-clang-libc++/qmake.conf
sed -i -e "s/QMAKE_LFLAGS      += -stdlib=libc++/QMAKE_LFLAGS      += -stdlib=libc++ -lpthread $CXXFLAGS/g" linux-clang-libc++/qmake.conf

# set optimization to O1
sed -i -e "s/QMAKE_CFLAGS_OPTIMIZE      = -O2/QMAKE_CFLAGS_OPTIMIZE      = -O1/g" common/gcc-base.conf
sed -i -e "s/QMAKE_CFLAGS_OPTIMIZE_FULL = -O3/QMAKE_CFLAGS_OPTIMIZE_FULL = -O1/g" common/gcc-base.conf

# remove -fno-rtti which conflicts with -fsanitize=vptr when building with sanitizer undefined
sed -i -e "s/QMAKE_CXXFLAGS_RTTI_OFF    = -fno-rtti/QMAKE_CXXFLAGS_RTTI_OFF    = /g" common/gcc-base.conf

# build project
cd $WORK
$SRC/qt/configure -qt-libmd4c -platform linux-clang-libc++ -release -static -opensource -confirm-license -no-opengl -prefix $PWD/qtbase -D QT_NO_DEPRECATED_WARNINGS
VERBOSE=1 cmake --build . --parallel

# prepare corpus files
zip -j $WORK/cbor $SRC/qtqa/fuzzing/testcases/cbor/*
zip -j $WORK/datetime $SRC/qtqa/fuzzing/testcases/datetime/*
zip -j $WORK/html $SRC/qtqa/fuzzing/testcases/html/*
zip -j $WORK/icc $SRC/qtqa/fuzzing/testcases/icc/*
zip -j $WORK/images $SRC/qtqa/fuzzing/testcases/{bmp,gif,ico,jpg,png,svg,xbm,xpm}/* $SRC/afltestcases/images/*/*
zip -j $WORK/markdown $SRC/qtqa/fuzzing/testcases/markdown/*
zip -j $WORK/regexp.zip $SRC/qtqa/fuzzing/testcases/regexp/*
zip -j $WORK/ssl.pem.zip $SRC/qtqa/fuzzing/testcases/ssl.pem/*
zip -j $WORK/svg $SRC/qtqa/fuzzing/testcases/svg/*
zip -j $WORK/text $SRC/qtqa/fuzzing/testcases/text/* $SRC/afltestcases/others/text/*
zip -j $WORK/xml $SRC/qtqa/fuzzing/testcases/xml/* $SRC/afltestcases/others/xml/*

# prepare merged dictionaries
mkdir $WORK/merged_dicts
cat $SRC/afldictionaries/{css,html_tags}.dict > "$WORK/merged_dicts/css_and_html.dict"
cat $SRC/afldictionaries/{bmp,exif,gif,jpeg,png,svg,tiff,webp}.dict > "$WORK/merged_dicts/images.dict"

# build fuzzers

build_fuzzer() {
    local module=$1
    local srcDir="$2"
    local format=${3-""}
    local dictionary=${4-""}
    local exeName="${srcDir##*/}"
    local targetName="${module}_${srcDir//\//_}"
    mkdir build_fuzzer
    cd build_fuzzer
    $WORK/qtbase/bin/qt-cmake -S "$SRC/qt/$module/tests/libfuzzer/$srcDir" -GNinja
    VERBOSE=1 cmake --build . --parallel

    mv "$exeName" "$OUT/$targetName"
    if [ -n "$format" ]; then
        cp "$WORK/$format.zip" "$OUT/${targetName}_seed_corpus.zip"
    fi
    if [ -n "$dictionary" ]; then
        cp "$dictionary" "$OUT/$targetName.dict"
    fi
    cd ..
    rm -r build_fuzzer
}

build_fuzzer "qtbase" "corelib/serialization/qcborstreamreader/next" "cbor"
build_fuzzer "qtbase" "corelib/serialization/qcborvalue/fromcbor" "cbor"
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
