//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

func formatSeconds(seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return String(format: "%02d:%02d", minutes, seconds)

}

struct ExpandedVoiceMessageRecordingView: View {
    var buttonPadding: CGFloat = 40
    var deleteFunc: () -> Void
    var sendFunc: () -> Void
    var recordFunc: (Bool) -> Void

    @State var isRecording = true
    @State var timeElapsed: Int
    @State var timeFormatted = ""
    @State var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Text(verbatim: "\(timeFormatted)")
                .font(.largeTitle)
                .bold()
                .padding(.trailing, 10)
                .frame(alignment: .center)
                .border(.clear)
                .onReceive(timer) { _ in
                    if isRecording {
                        timeElapsed += 1
                        timeFormatted = formatSeconds(seconds: timeElapsed)
                    }
                }
            HStack {
                Button(action: { // Delete Recording
                    self.deleteFunc()
                }, label: {
                    Label("", systemImage: "trash").font(.title2)
                })
                Spacer()
                Button(action: { // End/Restart Recording
                    isRecording.toggle()

                    if isRecording {
                        timeElapsed = 0
                        timeFormatted = formatSeconds(seconds: 0)
                        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                    }

                    self.recordFunc(isRecording)

                }, label: {
                    Label("", systemImage: isRecording ? "square.fill" : "arrow.clockwise.square").font(.title2)
                })
                Spacer()
                Button(action: { // Send Recording
                    self.sendFunc()

                }, label: {
                    Label("", systemImage: "paperplane").font(.title2)
                })
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, buttonPadding)
            .padding(.bottom, 10)
            .border(.clear)

        }
        .frame(maxWidth: .infinity)
        .border(.clear)
        .background(Color(NCAppBranding.backgroundColor()))
        .onAppear {
            timeFormatted = formatSeconds(seconds: timeElapsed)
        }
    }
}

//#Preview {
//    ExpandedVoiceMessageRecordingView(deleteFunc: {
//        // unused atm
//    }, sendFunc: {
//        // unused atm
//    }, recordFunc: { _ in
//        // unused atm
//    }, timeElapsed: 0)
//}
