/* Agave Linux Calamares slideshow (slideshowAPI 2).
 * Minimal, on-brand: Adwaita Pastel Dark background with rotating feature
 * cards. No external images required. */
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    property int currentSlide: 0

    Timer {
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: {
            presentation.currentSlide = (presentation.currentSlide + 1) % slideModel.count
        }
    }

    function onActivate() { presentation.currentSlide = 0 }
    function onLeave() {}

    ListModel {
        id: slideModel
        ListElement {
            title: "Welcome to Agave Linux"
            body: "An Arch-based system with the Mango compositor and the Wayle\nGTK4 shell. This installer copies the live desktop to your disk —\nwhat you booted is what you get."
        }
        ListElement {
            title: "Snapshots, built in"
            body: "Your system installs on btrfs with Snapper and snap-pac.\nEvery package change is snapshotted automatically, and GRUB\nlets you boot straight into an earlier snapshot to roll back."
        }
        ListElement {
            title: "Three kernels, ready to go"
            body: "linux, linux-lts and linux-zen are all installed with GRUB\nentries. Pick whichever suits your hardware at boot."
        }
        ListElement {
            title: "Almost there"
            body: "Sit back while Agave Linux is installed. When it finishes,\nreboot and log straight into your new Mango + Wayle desktop."
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: 24

            Rectangle {
                width: 64; height: 64
                radius: 16
                color: "#62a0ea"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: slideModel.get(presentation.currentSlide).title
                color: "#ffffff"
                font.pixelSize: 30
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: slideModel.get(presentation.currentSlide).body
                color: "#c7c7c7"
                font.pixelSize: 16
                lineHeight: 1.3
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: slideModel.count
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: index === presentation.currentSlide ? "#0ab9dc" : "#4f4f4f"
                    }
                }
            }
        }
    }
}
