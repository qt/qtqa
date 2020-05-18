import QtQuick 2.0
Rectangle{id:r
Text{id:t
x:66
y:93
text:"A"}states:[State{name:"a"
PropertyChanges{target:r
color:"blue"}PropertyChanges{target:t
text:"C"}},State{name:"b"
PropertyChanges{target:r
color:"gray"}PropertyChanges{target:t
text:"C"}}]}