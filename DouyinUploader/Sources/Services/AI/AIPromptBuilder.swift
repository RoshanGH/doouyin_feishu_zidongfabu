import Foundation

/// 构建发送给 AI 的 prompt
enum AIPromptBuilder {

    /// 构建页面分析 prompt
    static func buildPageAnalysis(
        taskDescription: String,
        currentStep: String,
        content: String,
        tags: [String]
    ) -> String {
        let tagsStr = tags.isEmpty ? "无" : tags.joined(separator: ", ")

        return """
        你是一个抖音创作者中心的自动化操作助手。请分析这张页面截图。

        当前任务：\(taskDescription)
        当前步骤：\(currentStep)
        作品文案：\(content.prefix(50))
        话题标签：\(tagsStr)

        请判断：
        1. 页面当前处于什么状态
        2. 是否有弹窗遮挡（活动弹窗、新功能引导、确认对话框）
        3. 是否出现验证码
        4. 是否跳转到了登录页
        5. 需要执行什么操作

        返回严格的 JSON 格式（不要包含其他文字）：
        {
            "status": "normal|popup|captcha|loginExpired|uploadComplete|publishSuccess|error",
            "description": "用一句话描述当前页面状态",
            "action": {
                "type": "click|type|pressKey|wait|waitForUser|completed|error",
                "x": 坐标X（仅 click 时需要）,
                "y": 坐标Y（仅 click 时需要）,
                "text": "输入文本（仅 type 时需要）",
                "key": "按键名（仅 pressKey 时需要）",
                "seconds": 等待秒数（仅 wait 时需要）,
                "message": "消息（waitForUser/completed/error 时需要）"
            }
        }

        注意：
        - 截图宽度为 640 像素，坐标基于此分辨率
        - 如果有弹窗遮挡，优先处理弹窗（找到关闭按钮的坐标）
        - 如果是验证码，返回 waitForUser
        - 如果看到登录页，返回 error + loginExpired
        """
    }

    /// 构建元素定位 prompt
    static func buildFindElement(elementDescription: String) -> String {
        return """
        看这张抖音创作者中心的页面截图（宽度 640 像素），找到以下元素：

        \(elementDescription)

        返回严格的 JSON 格式：
        {
            "status": "normal",
            "description": "元素位置描述",
            "action": {
                "type": "click",
                "x": 元素中心X坐标,
                "y": 元素中心Y坐标
            }
        }

        如果找不到该元素，返回：
        {
            "status": "error",
            "description": "未找到目标元素",
            "action": {
                "type": "error",
                "message": "未找到: \(elementDescription)"
            }
        }
        """
    }

    /// 构建操作验证 prompt
    static func buildVerifyAction(expectedChange: String) -> String {
        return """
        看这张页面截图，判断上一步操作是否成功：

        预期变化：\(expectedChange)

        返回严格的 JSON 格式：
        {
            "status": "normal|popup|captcha|publishSuccess|error",
            "description": "描述当前页面状态",
            "action": {
                "type": "completed",
                "message": "操作成功"
            }
        }

        如果操作未成功（页面没有预期变化），返回 error。
        如果出现了新的弹窗或验证码，返回对应的 status 和处理 action。
        """
    }
}
