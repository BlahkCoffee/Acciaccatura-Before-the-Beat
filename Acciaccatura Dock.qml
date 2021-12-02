//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Copyright (C) 2012 Werner Schweer
//  Copyright (C) 2013-2017 Nicolas Froment, Joachim Schmitz
//  Copyright (C) 2019 Bernard Greenberg
//  Copyright (C) 2020 Kate Dudek
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation and appearing in
//  the file LICENCE.GPL
//=============================================================================

import QtQuick 2.2
import MuseScore 3.0
import QtQuick.Controls 1.1
import QtQuick.Controls.Styles 1.3
import QtQuick.Layouts 1.1
import QtQuick.Dialogs 1.2

MuseScore {
version:  "3.6.2"
description: "This plugin adjusts the duration of an acciaccatura."
menuPath: "Plugins.Acciaccatura Dock"
pluginType: "dock";
dockArea: "left";
    implicitHeight : 160;
    implicitWidth : 240;

requiresScore: true

    property int margin : 10

    property var the_note: null;

    width :  240
    height : 160

onRun: {
        if ((mscoreMajorVersion < 3) || (mscoreMinorVersion < 3)) {
            versionError.open();
            return;
        }
        console.log("hello adjust acciaccatura: onRun");
        var note_info = find_usable_note();
        if (note_info) {
            the_note = note_info.note;
            mainNoteStart.text = note_info.main_start + "";
            separation.text = note_info.separation + "";
        }
    }

    // Apply the given function to all notes (elements with pitch) in selection or, if nothing is selected, in the entire score
    function applyToNotesInSelection(func)
    {
        var cursor = curScore.newCursor();
        cursor.rewind(1);
        var startStaff;
        var endStaff;
        var endTick;
        var fullScore = false;
        if (!cursor.segment) {     // no selection
            fullScore = true;
            startStaff = 0;       // start with 1st staff
            endStaff = curScore.nstaves - 1;       // and end with last
        } else {
            startStaff = cursor.staffIdx;
            cursor.rewind(2);
            if (cursor.tick === 0) {
                // this happens when the selection includes the last measure of the score.
                // rewind(2) goes behind the last segment (where there's none) and sets tick=0
                endTick = curScore.lastSegment.tick + 1;
            } else {
                endTick = cursor.tick;
            }
            endStaff = cursor.staffIdx;
        }
        console.log(startStaff + " - " + endStaff + " - " + endTick)
        for (var staff = startStaff; staff <= endStaff; staff++) {
            for (var voice = 0; voice < 4; voice++) {
                cursor.rewind(1);         // sets voice to 0
                cursor.voice = voice;         //voice has to be set after goTo
                cursor.staffIdx = staff;

                if (fullScore)
                    cursor.rewind(0)           // if no selection, beginning of score

                    while (cursor.segment && (fullScore || cursor.tick < endTick)) {
                        if (cursor.element && cursor.element.type === Element.CHORD) {
                            var graceChords = cursor.element.graceNotes;
                            for (var i = 0; i < graceChords.length; i++) {
                                // iterate through all grace chords
                                var graceNotes = graceChords[i].notes;
                                for (var j = 0; j < graceNotes.length; j++) {
                                    func(graceNotes[j]);
                                }
                            }
                            if (graceChords.length !== 0) {                                 // new part
                                var notes = cursor.element.notes;
                                for (var k = 0; k < notes.length; k++) {
                                    var note = notes[k];
                                    func(note);
                                }
                            }                                // new part
                        }
                        cursor.next();
                    }
                }
            }
        }

    function acciaccatura(note)
    {
        var note_info = find_usable_note();
        if (note_info) {
            the_note = note_info.note;
            applyChanges(note);
        }
    }

    function find_usable_note()
    {
        var selection = curScore.selection;
        var elements = selection.elements;
        if (elements.length > 0) {  // We have a selection list to work with...
            console.log(elements.length, "selected elements")
            for (var idx = 0; idx < elements.length; idx++) {
                var element = elements[idx]
                              console.log("element.type=" + element.type)
                              if (element.type === Element.NOTE) {
                    var note = element;
                    var summa_gratiarum = sum_graces(note);
                    if (summa_gratiarum) {
                        var mnplayevs = note.playEvents;
                        var mpe0 = mnplayevs[0];
                        dump_play_ev(mpe0);
                        return {
note:                              note,
main_start:                        mpe0.ontime,
separation:                        mpe0.ontime + summa_gratiarum,
                        }
                    }
                }
            }
        }
        return false;  // trigger dismay
    }

    function sum_graces(note)
    {
        var chord = note.parent;
        var grace_chords = chord.graceNotes;  //it lies.
        if (!grace_chords || grace_chords.length === 0) {
            return false;
        }

        console.log("N grace chords", grace_chords.length);
        var summa = 0
                    for (var i = 0; i < grace_chords.length; i++) {
            var grace_chord = grace_chords[i];
            var grace_note = grace_chord.notes[0];
            var gpe0 = grace_note.playEvents[0];
            dump_play_ev(gpe0);
            summa += gpe0.len;
        }
        console.log("summa", summa);
        return summa;
    }

    function dump_play_ev(event)
    {
        console.log("on time", event.ontime, "len", event.len, "off time", event.ontime + event.len);
    }

    function applyChanges()
    {
        var note = the_note;
        if (!note) {
            return false;
        }
        var new_transit = parseInt(mainNoteStart.text);
        if (isNaN(new_transit) || new_transit < 0) {
            return false;
        }
        var new_separation = parseInt(separation.text);
        if (isNaN(new_separation)) { //could be pappadum
            return false;
        }

        applyToNotesInSelection(function(note, cursor) {
            var mpe0 = note.playEvents[0];
            var orig_transit = mpe0.ontime; // must be so if we are here.
            var inc = new_transit - orig_transit;
            var grace_chords = note.parent.graceNotes; //really
            var ngrace = grace_chords.length; //chords, really
            var new_grace_end = new_separation; // negative means more +
            var new_grace_len = Math.floor(new_grace_end / ngrace);

            // Compute values and check validity first.
            var main_off_time = mpe0.ontime + mpe0.len; //doesn't change
            var new_main_on_time = 0; //attendite et videte
            var new_main_len = main_off_time - new_main_on_time; // old len

            if (new_main_len <= 0 || new_grace_len <= 0) {
                console.log("Values produce negative main or grace length.");
                return false;
            }

            curScore.startCmd();
            var current = 0;
            for (var i = 0; i < ngrace; i++) {
                var chord = grace_chords[i];
                for (var j = 0; j < chord.notes.length; j++) {
                    var gn0 = chord.notes[j];
                    var pe00 = gn0.playEvents[0];
                    pe00.len = new_grace_len;
                    pe00.ontime = i * new_grace_len - ngrace * new_grace_len;
                }
            }

            var notachord = note.parent;
            var chord_notes = notachord.notes;
            for (var k = 0; k < chord_notes.length; k++) {
                var cnote = chord_notes[k];
                var mpce0 = cnote.playEvents[0];
                mpce0.ontime = 0;
                mpce0.len = mainNoteStart.text;
            }
        })
        curScore.endCmd()
        return true;
    }

    GridLayout {
id:     'mainLayout'
        anchors.fill:parent
        anchors.margins : 10
        columns : 2

        Label {
text:       "Main Note Length"
        }
        TextField {
id:         mainNoteStart
            implicitHeight : 24
placeholderText: "1000"
focus:      true
            Keys.onEscapePressed: {
                Qt.quit();
            }
            Keys.onReturnPressed: {
            }
        }
        Label {
text:       "Separation"
        }
        TextField {
id:         separation
            implicitHeight : 24
placeholderText: "0"
focus:      false
            Keys.onEscapePressed: {
                Qt.quit();
            }
            Keys.onReturnPressed: {
            }
        }

        Button {
id:         applyButton
visible:    true
            Layout.columnSpan : 1
text:       qsTranslate("PrefsDialogBase", "Apply")
            onClicked : {
                applyToNotesInSelection(acciaccatura)
            }
        }

        Button {
id:         cancelButton
visible:    true
            Layout.rowSpan : 1
text:       qsTranslate("PrefsDialogBase", "Cancel")
            onClicked : {
                Qt.quit()
            }
        }
    }     // end of grid

    MessageDialog {
id:     versionError
visible: false
title:  qsTr("Unsupported MuseScore Version")
        text : qsTr("This plugin needs MuseScore 3.3 or later")
        onAccepted : {
            Qt.quit();
        }
    }
}
