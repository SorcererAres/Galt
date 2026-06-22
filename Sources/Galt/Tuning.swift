import Foundation

/// 内部调参常量集中区。
///
/// 这些是固定的「手感 / 时长 / 灵敏度」参数——不是用户设置（不持久化、不进设置界面），
/// 而是产品手感的内部取值。集中于此便于统一维护与实机调试，避免散落在各控制器的方法里。
/// 用户可调的设置仍在 `SettingsStore`。
enum Tuning {
    /// 单次听写会话
    enum Session {
        /// 单次最长录音时长（秒），对齐 Typeless 的 6 分钟
        static let maxSeconds: TimeInterval = 360
        /// 临近上限时，剩余多少秒开始在录音胶囊上显示倒计时
        static let countdownWarnSeconds: TimeInterval = 60
    }

    /// 热键判定
    enum Hotkey {
        /// 点按判定阈值：按下到松开短于该值视为「点按」→ 进入锁定听写
        static let tapThreshold: TimeInterval = 0.35
    }

    /// 麦克风唤醒（异步启动）
    enum Startup {
        /// 防抖：超过该时长仍未就绪才呈现「唤醒中」胶囊，启动够快则直接进录音态、不闪 loading
        static let debounce: TimeInterval = 0.12
    }

    /// 录音音量可视化
    enum MicLevel {
        /// dB 归一值整体放大倍率（越大越易打满，1 = 原始）
        static let sensitivity: Float = 1.6
        /// 噪声底（dB）：低于此值视为静默（→0），0dB→1
        static let noiseFloorDB: Float = -50
    }

    /// 新手教学提示
    enum Hint {
        /// 最多展示次数（之后不再打扰）
        static let maxShows = 3
        /// 提示文案
        static let text = "按住说话，松开结束 · 轻点可锁定"
        /// 展示后自动清除的时长（秒）
        static let duration: TimeInterval = 2.5
    }

    /// HUD 各态自动淡出延时（秒）
    enum HUDDismiss {
        /// 成功出字后停留
        static let success: TimeInterval = 3
        /// 「未捕获到语音」轻量反馈停留
        static let empty: TimeInterval = 1.2
        /// 取消录音后的轻量反馈停留
        static let cancelled: TimeInterval = 1.2
        /// 启动录音失败等不可重试错误停留
        static let error: TimeInterval = 3
        /// 启动录音失败提示停留
        static let startFailure: TimeInterval = 2.5
        /// 失败态等待用户操作的超时兜底
        static let failure: TimeInterval = 12
        /// 学到新词的轻量提示停留
        static let learnedInfo: TimeInterval = 2
    }

    /// 出字落定后给焦点字段拍快照的延时（让粘贴/键入真正写入字段后再读取）
    static let snapshotDelay: TimeInterval = 0.4
}
