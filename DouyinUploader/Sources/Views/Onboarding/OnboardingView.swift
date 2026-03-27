import SwiftUI

/// 引导 Sheet —— 4 步向导
struct OnboardingView: View {

    @EnvironmentObject private var settingsManager: SettingsManagerStore
    @Binding var isPresented: Bool
    @State private var currentStep: Int = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // 顶部步骤指示器
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Text("步骤 \(currentStep + 1) / \(totalSteps)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)

            // 步骤内容
            Group {
                switch currentStep {
                case 0: step1_feishuConfig
                case 1: step2_tableFields
                case 2: step3_douyinLogin
                case 3: step4_ready
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 底部按钮
            HStack {
                if currentStep < totalSteps - 1 {
                    Button("跳过") { complete() }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if currentStep > 0 {
                    Button("上一步") { withAnimation { currentStep -= 1 } }
                        .buttonStyle(.bordered)
                }
                if currentStep < totalSteps - 1 {
                    Button("下一步") { withAnimation { currentStep += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("开始使用") { complete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - 步骤 1：配置飞书

    private var step1_feishuConfig: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("配置飞书多维表格")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. 登录飞书开放平台，创建自建应用获取 App ID + App Secret")
                Text("2. 或在「个人设置」中生成 Personal Access Token (PAT)")
                Text("3. 在 App 的「飞书配置」页粘贴表格 URL 并测试连接")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: - 步骤 2：表格字段规范

    private var step2_tableFields: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("按规范创建飞书表格")
                .font(.title3)
                .fontWeight(.semibold)

            Text("请在飞书多维表格中创建以下列（列名必须完全一致）：")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            // 字段列表
            ScrollView {
                VStack(spacing: 0) {
                    // 表头
                    HStack(spacing: 0) {
                        Text("列名").fontWeight(.semibold).frame(width: 120, alignment: .leading)
                        Text("类型").fontWeight(.semibold).frame(width: 44, alignment: .leading)
                        Text("必填").fontWeight(.semibold).frame(width: 32)
                        Text("说明").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))

                    ForEach(FeishuColumn.all, id: \.name) { col in
                        HStack(spacing: 0) {
                            // 列名 + 复制按钮
                            HStack(spacing: 4) {
                                Text(col.name)
                                    .fontWeight(col.required ? .medium : .regular)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(col.name, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("复制列名「\(col.name)」")
                            }
                            .frame(width: 120, alignment: .leading)

                            Text(col.type)
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)

                            Text(col.required ? "是" : "")
                                .foregroundColor(.red)
                                .frame(width: 32)

                            Text(col.description)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                        Divider().padding(.leading, 12)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - 步骤 3：登录抖音

    private var step3_douyinLogin: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("登录抖音账号")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. 在「账号管理」页点击「添加账号」")
                Text("2. 在弹窗中用抖音 App 扫描二维码")
                Text("3. 如需短信验证，在弹窗中输入验证码")
                Text("4. 可添加多个账号，登录后自动匹配飞书表格中的抖音号")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: - 步骤 4：完成

    private var step4_ready: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("一切就绪！")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("现在你可以：")
                    .fontWeight(.medium)
                Text("1. 在「飞书配置」页添加表格配置")
                Text("2. 在「账号管理」页登录抖音账号")
                Text("3. 在「执行发布」页一键批量发布")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: - 完成

    private func complete() {
        settingsManager.settings.hasCompletedOnboarding = true
        settingsManager.saveSettings()
        isPresented = false
    }
}
