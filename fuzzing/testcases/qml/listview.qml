import QtQuick 2.0
Item{width:1
height:1
ListView{anchors.fill:parent;
model:ListModel{ListElement{name:"A"
speed:1}}delegate:Item{height:1
Row{spacing:1
Text{text:name;
font.bold:true}Text{text:"A"+speed}}}}}