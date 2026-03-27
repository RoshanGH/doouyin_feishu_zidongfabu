/**
 * douyin_video_publish.js
 * 抖音视频发布完整流程脚本
 *
 * 调用方式：Swift 通过 evaluateJavaScript 传入 publishVideoParams 后执行此脚本
 * publishVideoParams 格式：
 * {
 *   "content":       string,  // 发布文案
 *   "hasSchedule":   boolean, // 是否定时发布
 *   "scheduleTime":  string,  // 定时时间字符串（格式: "YYYY-MM-DD HH:mm"）
 *   "stepTimeout":   number   // 每步最大等待毫秒数（默认 30000）
 * }
 */

(function() {
    'use strict';

    // =========================================================
    // 参数读取（由 Swift 在执行前注入 window.publishVideoParams）
    // =========================================================

    var params = window.publishVideoParams || {};
    var content = params.content || '';
    var hasSchedule = params.hasSchedule || false;
    var scheduleTime = params.scheduleTime || '';
    var hasMusic = params.hasMusic || false;
    var musicName = params.musicName || '';
    var isVideo = params.isVideo !== false;
    var stepTimeout = params.stepTimeout || 30000;

    // =========================================================
    // 选择器（与 selectors.json 保持同步）
    // =========================================================

    var SEL = {
        fileInput:        "div[class^='container'] input",
        uploadComplete:   "[class^='long-card'] div",
        descEditor:       ".zone-container",
        scheduleRadio:    "[class^='radio']",
        scheduleInput:    ".semi-input",
        publishBtn:       "button[class*='primary']"
    };

    // =========================================================
    // 主流程（async IIFE，异常通过 notifySwift 上报）
    // =========================================================

    async function runVideoPublish() {
        try {
            // 注意：文件上传已由 Swift 端通过 DataTransfer API 完成
            // 此脚本在发布信息页执行，负责填写文案/音乐/定时/发布

            // 等待页面就绪（描述编辑器出现）
            window.notifySwift('stepDone', { step: 'waitPageReady', status: 'start' });
            await window.waitForElement(SEL.descEditor, stepTimeout);
            window.notifySwift('stepDone', { step: 'waitPageReady', status: 'done' });

            await window.sleep(1000 + Math.random() * 500);

            // 步骤 1：填写文案
            window.notifySwift('stepDone', { step: 'fillContent', status: 'start' });
            await fillDescription(content);
            window.notifySwift('stepDone', { step: 'fillContent', status: 'done' });

            await window.sleep(500 + Math.random() * 500);

            // 步骤 6：音乐选择（如有）
            if (hasMusic && musicName && typeof window.selectMusic === 'function') {
                window.notifySwift('stepDone', { step: 'selectMusic', status: 'start' });
                var musicResult = await window.selectMusic(musicName, isVideo);
                if (musicResult.success) {
                    window.notifySwift('stepDone', { step: 'selectMusic', status: 'done' });
                } else {
                    // 音乐选择失败不阻断发布，仅记录警告
                    window.notifySwift('stepDone', {
                        step: 'selectMusic',
                        status: 'warning',
                        message: musicResult.reason || '音乐选择失败'
                    });
                }
                await window.sleep(500 + Math.random() * 500);
            }

            // 步骤 7（原6）：处理定时发布
            if (hasSchedule && scheduleTime) {
                window.notifySwift('stepDone', { step: 'setSchedule', status: 'start' });
                await setScheduledTime(scheduleTime, stepTimeout);
                window.notifySwift('stepDone', { step: 'setSchedule', status: 'done' });
                await window.sleep(500 + Math.random() * 500);
            }

            // 步骤 7：点击发布按钮
            window.notifySwift('stepDone', { step: 'clickPublish', status: 'start' });
            await clickPublishButton(stepTimeout);
            window.notifySwift('stepDone', { step: 'clickPublish', status: 'done' });

            // 步骤 8：等待发布结果
            window.notifySwift('stepDone', { step: 'watchResult', status: 'start' });
            window.watchPublishResult(params.resultTimeout || 60000);

        } catch (err) {
            window.notifySwift('error', {
                step: 'videoPublish',
                message: err.message || String(err)
            });
        }
    }

    // =========================================================
    // 等待视频上传完成
    // =========================================================

    function waitForUploadComplete(timeout) {
        return new Promise(function(resolve, reject) {
            var deadline = Date.now() + timeout;

            var checkInterval = setInterval(function() {
                // 检查是否出现"重新上传"文字（表示上传成功）
                var cards = document.querySelectorAll("[class^='long-card']");
                for (var i = 0; i < cards.length; i++) {
                    if (cards[i].textContent.indexOf('重新上传') !== -1) {
                        clearInterval(checkInterval);
                        resolve();
                        return;
                    }
                }

                // 检查是否有上传失败提示
                var bodyText = document.body ? document.body.innerText : '';
                if (bodyText.indexOf('上传失败') !== -1 || bodyText.indexOf('文件格式不支持') !== -1) {
                    clearInterval(checkInterval);
                    reject(new Error('视频上传失败：' + bodyText.substring(0, 100)));
                    return;
                }

                if (Date.now() > deadline) {
                    clearInterval(checkInterval);
                    reject(new Error('等待视频上传完成超时'));
                }
            }, 2000);
        });
    }

    // =========================================================
    // 填写发布文案
    // =========================================================

    async function fillDescription(text) {
        if (!text) return;

        // 等待编辑器出现
        var editor = await window.waitForElement(SEL.descEditor, 15000);
        editor.focus();

        await window.sleep(300);

        // 使用 contenteditable 方式插入文本
        window.setContentEditableValue(editor, text);

        // 等待内容渲染
        await window.sleep(500);
    }

    // =========================================================
    // 设置定时发布
    // =========================================================

    async function setScheduledTime(timeStr, timeout) {
        // 点击"定时发布"单选按钮
        var radioClicked = false;
        var radios = document.querySelectorAll("[class^='radio']");
        for (var i = 0; i < radios.length; i++) {
            if (radios[i].textContent.indexOf('定时发布') !== -1) {
                radios[i].click();
                radioClicked = true;
                break;
            }
        }

        if (!radioClicked) {
            // 尝试通过 label 查找
            var labels = document.querySelectorAll('label');
            for (var j = 0; j < labels.length; j++) {
                if (labels[j].textContent.indexOf('定时发布') !== -1) {
                    labels[j].click();
                    radioClicked = true;
                    break;
                }
            }
        }

        if (!radioClicked) {
            throw new Error('未找到定时发布选项');
        }

        await window.sleep(800);

        // 等待时间输入框出现
        var timeInput = await window.waitForElement(SEL.scheduleInput, timeout);
        timeInput.focus();
        await window.sleep(300);

        // 输入时间值
        window.setReactInputValue(timeInput, timeStr);
        timeInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await window.sleep(500);
    }

    // =========================================================
    // 点击发布按钮
    // =========================================================

    async function clickPublishButton(timeout) {
        // 优先通过文字找"发布"按钮
        var clicked = window.clickByText('发布', 'button');
        if (clicked) return;

        // 退而使用 primary 按钮
        var btn = await window.waitForElement(SEL.publishBtn, timeout);
        btn.click();
    }

    // =========================================================
    // 启动
    // =========================================================

    runVideoPublish();

})();
