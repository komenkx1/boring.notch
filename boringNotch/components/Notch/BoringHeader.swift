//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import AgentActivityCore
import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var agentActivityRuntime = AgentActivityRuntime.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        AgentActivityHeaderButton(
                            agentRuns: agentActivityRuntime.agentRuns,
                            selected: coordinator.currentView == .agents
                        ) {
                            withAnimation(.smooth) {
                                coordinator.currentView = coordinator.currentView == .agents
                                    ? .home
                                    : .agents
                            }
                        }
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

private struct AgentActivityHeaderButton: View {
    let agentRuns: [AgentRun]
    let selected: Bool
    let action: () -> Void

    @FocusState private var hasKeyboardFocus: Bool

    private var attentionCount: Int {
        agentRuns.filter { $0.needsAttention }.count
    }

    private var activeAgentCount: Int {
        agentRuns.filter { $0.activityState.isActive }.count
    }

    private var iconColor: Color {
        if attentionCount > 0 {
            return AgentActivityColor.attention
        }
        if activeAgentCount > 0 {
            return AgentActivityColor.running
        }
        return .white
    }

    private var accessibilityLabel: String {
        if attentionCount > 0 {
            return "Agent activity, \(attentionCount) waiting for attention"
        }
        if activeAgentCount > 0 {
            return "Agent activity, \(activeAgentCount) active"
        }
        return "Agent activity"
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color(nsColor: .secondarySystemFill) : .black)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                if attentionCount > 0 {
                    Text("\(min(attentionCount, 9))")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 13, height: 13)
                        .background(AgentActivityColor.attention, in: Circle())
                        .offset(x: 3, y: -3)
                } else if activeAgentCount > 0 {
                    Circle()
                        .fill(AgentActivityColor.running)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.black, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(hasKeyboardFocus ? Color.white : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($hasKeyboardFocus)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(selected ? "Show the home view" : "Show agent activity")
        .help("Agent Activity")
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
