/*
 * Copyright (C) 2013-2014 Canonical Ltd.
 * Copyright (C) 2020-2026 UBports Foundation
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import Lomiri.Components 1.3
import Utils 0.1
import "../../.."
import "../../../Components"

Item {
    id: root
    implicitHeight: units.gu(3)

    property int align: Qt.AlignRight
    property int orientation: Qt.Horizontal
    property bool clip: true
    property alias interactive: flickable.interactive
    property var collapsedCutouts: []
    property var expandedCutouts: []
    property real collapsedHeight: units.gu(3)
    property bool hideRow: false
    property QtObject model: null
    property real overFlowWidth: width
    property bool expanded: false
    property bool finishedExpanding: false
    property var screenOrientation: Qt.PrimaryOrientation

    property var currentItem: null
    property int currentItemIndex: 0
    property real unitProgress: 0.0
    property real selectionChangeBuffer: units.gu(2)
    property bool enableLateralChanges: false

    property real lastSelectedX: 0.0
    property alias delegate: repeater.delegate
    property alias contentX: flickable.contentX
    property alias contentWidth: flickable.contentWidth

    property real lateralPosition: -1
    property int screenIndex: -1

    DisplayCutoutsModel {
        id: cutoutsModel
        expanded: root.expanded
        orientation: screenOrientation
        enabled: screenIndex === 0
        lightMode: theme.palette.normal.background.hslLightness >= 0.5

        onModelReset: {
            d.recalculateItems();
        }
    }

    Connections {
        target: DebuggingController

        function onDeviceInfoReloadRequested() {
            cutoutsModel.reloadConfig();
        }
    }

    onCurrentItemIndexChanged: {
        currentItem = repeater.itemAt(currentItemIndex);
        d.recalculateItems();
    }

    onHeightChanged: {
        d.recalculateItems();
    }

    onWidthChanged: {
        d.recalculateItems();
    }

    onFinishedExpandingChanged: {
        if (!expanded) {
            flickable.contentX = 0;
        }
        d.recalculateItems();
    }

    onLateralPositionChanged: {
        updateItemFromLateralPosition();
    }

    onEnableLateralChangesChanged: {
        updateItemFromLateralPosition();
    }

    Connections {
        target: model
        function onCountChanged() {
            d.recalculateItems();
        }
    }

    function updateItemFromLateralPosition() {
        if (!enableLateralChanges || !root.finishedExpanding || lateralPosition === -1)
            return;

        selectItemAt(lateralPosition);
    }

    function indicatorAt(x, y) {
        const pos = flickable.contentItem.mapFromItem(root, x, y);
        const indicator = flickable.contentItem.childAt(pos.x, pos.y);

        if (indicator) {
            return indicator;
        }

        // Backwards compatibility, consumers of this function don't expect holes
        let closestBefore = null;
        let closestAfter = null;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(d.isFlipped ? i : repeater.count - i - 1);
            if (item.x > pos.x) {
                closestBefore = item;
                closestAfter = repeater.itemAt(i + 1);
            }
        }
        if (!closestBefore) {
            return null;
        }
        if (!closestAfter || closestBefore.x + closestBefore.width - pos.x < pos.x - closestAfter.x) {
            return closestBefore;
        }

        return closestAfter;
    }

    function resetCurrentItem() {
        flickable.contentX = 0;
        root.lastSelectedX = 0.0;
        root.currentItemIndex = -1;
    }

    function selectPreviousItem() {
        let indexToSelect = currentItemIndex - 1;
        while (indexToSelect >= 0) {
            if (setCurrentItemIndex(indexToSelect)) {
                return;
            }
            indexToSelect -= 1;
        }
    }

    function selectNextItem() {
        let indexToSelect = currentItemIndex + 1;
        while (indexToSelect < repeater.count) {
            if (setCurrentItemIndex(indexToSelect)) {
                return;
            }
            indexToSelect += 1;
        }
    }

    function setCurrentItemIndex(index) {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (item.hasOwnProperty('ownIndex') && item.ownIndex === index && item.enabled) {
                root.currentItemIndex = index;
                return true;
            }
        }

        return false;
    }

    function selectItemAt(x) {
        root.lastSelectedX = x;
        const item = indicatorAt(x, flickable.height / 2);
        if (item && item.opacity > 0 && item.enabled) {
            root.currentItemIndex = item.ownIndex;
        } else {
            const searchIndex = x < width / 2 ? 0 : repeater.count - 1;
            setCurrentItemIndex(searchIndex);
        }
    }

    QtObject {
        id: d

        property bool isFlipped: {
            root.align === Qt.AlignRight && root.orientation === Qt.Horizontal || root.align === Qt.AlignBottom && root.orientation === Qt.Vertical;
        }
        property bool isHorizontal: root.orientation === Qt.Horizontal

        function recalculateLater() {
            Qt.callLater(recalculateItems);
        }

        function recalculateItems() {
            const sizeField = isHorizontal ? 'width' : 'height';
            const posField = isHorizontal ? 'x' : 'y';
            const flickableField = isHorizontal ? 'contentX' : 'contentY';
            let currentX = 0;
            let screenX = 0;
            let itemMaxSize = 0;

            if (!root.finishedExpanding && root.currentItemIndex >= 0) {
                const mapped = flickable.mapToItem(root, root.lastSelectedX, 0);
                let sumBefore = 0;
                for (let i = 0; i < repeater.count; i++) {
                    if ((d.isFlipped && i >= root.currentItemIndex) || (!d.isFlipped && i < root.currentItemIndex)) {
                        sumBefore += repeater.itemAt(i)[sizeField];
                    }
                }
                for (let i = 0; i < cutoutsModel.rowCount(); i++) {
                    const cutout = cutoutsModel.data(cutoutsModel.index(i, 0));
                    if ((d.isFlipped && cutout[posField] + cutout[sizeField] > root.lastSelectedX) || (!d.isFlipped && cutout[posField] < root.lastSelectedX)) {
                        sumBefore += cutout[sizeField];
                    }
                }

                if (root.lastSelectedX > 0) {
                    flickable[flickableField] = sumBefore - mapped.x;
                }
            }

            for (let i = 0; i < repeater.count; i++) {
                const item = repeater.itemAt(d.isFlipped ? repeater.count - 1 - i : i);
                const itemSize = Math.ceil(item[sizeField]);

                if (itemSize > itemMaxSize) {
                    itemMaxSize = itemSize;
                }

                screenX = currentX - flickable[flickableField];

                for (let ci = 0; ci < cutoutsModel.rowCount(); ci++) {
                    const cutout = cutoutsModel.data(cutoutsModel.index(ci, 0));
                    const cutoutSize = Math.floor(cutout[sizeField]);
                    const cutoutPos = Math.floor(d.isFlipped ? root[sizeField] - cutout[posField] - cutoutSize : cutout[posField]);

                    if (screenX > cutoutPos + cutoutSize || screenX + itemSize <= cutoutPos) {
                        continue;
                    }

                    screenX = cutoutPos + cutoutSize;
                    currentX = screenX + flickable[flickableField];
                }

                item[posField] = currentX;
                item.rotation = d.isFlipped ? -180 : 0;
                currentX += itemSize;
            }

            const lastCutout = cutoutsModel.data(cutoutsModel.index(cutoutsModel.rowCount() - 1, 0));
            const lastSectionSize = Math.floor(root[sizeField] - (lastCutout ? lastCutout[posField] - lastCutout[sizeField] : 0));
            const lastItemSize = repeater.itemAt(repeater.count - 1) ? Math.ceil(repeater.itemAt(repeater.count - 1)[sizeField]) : 0;
            let cutoutsSize = 0;
            for (let i = 0; i < cutoutsModel.rowCount(); i++) {
                const cutout = cutoutsModel.data(cutoutsModel.index(i, 0));
                cutoutsSize += cutout[sizeField];
            }
            if (lastSectionSize < lastItemSize) {
                // TODO: this is not the proper solution
                //       with this, you can slide the last item too far in the direction of the alignment
                //       but otherwise the last item will be forced outside the bounds
                currentX += cutoutsSize;
            }
            // dipper: never let the content end before the visible edge.
            // With cutouts the item positions (so currentX) depend on the
            // current contentX; when contentX sat a few px past
            // contentWidth - width, Flickable's fixup pulled it back 1 px,
            // the recalculation shrank contentWidth by 1 px, and so on: the
            // row crept sideways on its own (~860 steps logged) and pushed the
            // first indicator (Notifications) off screen on the Mi 9.
            // A fixed contentWidth (all items + all cutouts) did not stop the
            // creep, this does; the flick limit below keeps it bounded.
            const visibleEnd = flickable[flickableField] + root[sizeField];
            flickable[isHorizontal ? 'contentWidth' : 'contentHeight'] = Math.max(currentX, visibleEnd);
            updateItemFromLateralPosition();
        }
    }

    Flickable {
        id: flickable
        pixelAligned: true
        anchors.fill: root
        interactive: false
        flickableDirection: d.isHorizontal ? Flickable.HorizontalFlick : Flickable.VerticalFlick
        rotation: d.isFlipped ? 180 : 0

        Behavior on contentX {
            enabled: !enableLateralChanges && root.finishedExpanding
            NumberAnimation {
                duration: LomiriAnimation.BriskDuration
                easing: LomiriAnimation.StandardEasing
            }
        }

        onContentXChanged: {
            // dipper: contentWidth follows contentX (see recalculateItems), so
            // bound the scroll here: every item and every cutout, plus one
            // item of slack, is as far as the row can ever need to go.
            let limit = -root.width;
            for (let i = 0; i < repeater.count; i++) {
                limit += Math.ceil(repeater.itemAt(i).width);
            }
            for (let i = 0; i < cutoutsModel.rowCount(); i++) {
                limit += Math.ceil(cutoutsModel.data(cutoutsModel.index(i, 0)).width);
            }
            limit += repeater.count > 0 ? Math.ceil(repeater.itemAt(0).width) : 0;
            if (contentX > Math.max(limit, 0)) {
                contentX = Math.max(limit, 0);
                return;
            }
            d.recalculateItems();
        }
        onContentYChanged: {
            d.recalculateItems();
        }
        onContentWidthChanged: {
            if (!interactive) {
                d.recalculateLater();
            }
        }

        Repeater {
            id: repeater
            model: root.model
            objectName: "panelRow"

            onItemAdded: {
                item.widthChanged.connect(d.recalculateItems);
            }
        }
    }

    Rectangle {
        id: highlight
        objectName: "highlight"

        anchors {
            top: root.top
            topMargin: flickable.height - height
        }
        height: units.dp(2)
        color: theme.palette.normal.foregroundText
        visible: currentItem !== null
        opacity: 0.0

        width: currentItem ? currentItem.width : 0
        Behavior on width {
            enabled: enableLateralChanges && expanded
            LomiriNumberAnimation {
                duration: LomiriAnimation.FastDuration
                easing: LomiriAnimation.StandardEasing
            }
        }

        // micromovements of the highlight line when user moves the finger across the items while pulling
        // the handle downwards.
        property real highlightCenterOffset: {
            if (!currentItem || lateralPosition == -1 || !enableLateralChanges)
                return 0;

            var itemMapped = root.mapToItem(currentItem, lateralPosition, 0);

            var distanceFromCenter = itemMapped.x - currentItem.width / 2;
            if (distanceFromCenter > 0) {
                distanceFromCenter = Math.max(0, distanceFromCenter - currentItem.width / 8);
            } else {
                distanceFromCenter = Math.min(0, distanceFromCenter + currentItem.width / 8);
            }

            if (currentItem && currentItem.ownIndex === 0 && distanceFromCenter < 0) {
                return 0;
            } else if (currentItem && currentItem.ownIndex === repeater.count - 1 & distanceFromCenter > 0) {
                return 0;
            }
            return (distanceFromCenter / (currentItem.width / 4)) * units.gu(1);
        }

        Behavior on highlightCenterOffset {
            NumberAnimation {
                duration: LomiriAnimation.FastDuration
                easing: LomiriAnimation.StandardEasing
            }
        }

        // FIXME: flickable.contentX != null is only there to trigger the binding because currentItem.mapToItem won't
        property real currentItemX: currentItem && flickable.contentX != null ? currentItem.mapToItem(root, 0, 0).x : 0

        Behavior on currentItemX {
            id: currentItemXBehavior
            enabled: enableLateralChanges && expanded && !flickable.moving && root.finishedExpanding
            NumberAnimation {
                duration: LomiriAnimation.FastDuration
                easing: LomiriAnimation.StandardEasing
            }
        }
        x: currentItemX + highlightCenterOffset
    }

    states: [
        State {
            name: "minimised"
            when: !expanded
        },
        State {
            name: "expanded"
            when: expanded
            PropertyChanges { target: highlight; opacity: 0.9 }
        }
    ]

    transitions: [
        Transition {
            PropertyAnimation {
                properties: "opacity";
                duration: LomiriAnimation.SnapDuration
                easing: LomiriAnimation.StandardEasing
            }
        }
    ]
}
