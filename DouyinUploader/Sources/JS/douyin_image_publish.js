/**
 * douyin_image_publish.js
 * 抖音图文发布完整流程脚本
 *
 * 调用方式：Swift 通过 evaluateJavaScript 传入 publishImageParams 后执行此脚本
 * publishImageParams 格式：
 * {
 *   "title":         string,  // 图文标题（可选）
 *   "content":       string,  // 发布文案
 *   "imageCount":    number,  // 上传的图片数量
 *   "hasSchedule":   boolean, // 是否定时发布
 *   "scheduleTime":  string,  // 定时时间字符串（格式: "YYYY-MM-DD HH:mm"）
 *   "stepTimeout":   number   // 每步最大等待毫秒数（默认 30000）
 * }
 */

(function() {
    'use strict';

    // =========================================================
    // 参数读取
    // =========================================================

    var params = window.publishImageParams || {};
    var title = params.title || '';
    var content = params.content || '';
    var imageCount = params.imageCount || 1;
    var hasSchedule = params.hasSchedule || false;
    var scheduleTime = params.scheduleTime || '';
    var hasMusic = params.hasMusic || false;
    var musicName = params.musicName || '';
    var isVideo = params.isVideo || false;
    var stepTimeout = params.stepTimeout || 30000;

    // =========================================================
    // 选择器
    // =========================================================

    var SEL = {
        modeSwitchText:  '发布图文',
        fileInput:       "div[class^='container'] input[accept*='image']",
        fileInputFallback: "div[class^='container'] input",
        uploadItem:      "[class*='upload-item'], [class*='image-item']",
        titleInput:      "input[placeholder*='标题'], input[placeholder*='title']",
        descEditor:      ".zone-container",
        scheduleRadio:   "[class^='radio']",
        scheduleInput:   ".semi-input",
        publishBtn:      "button[class*='primary']"
    };

    // =========================================================
    // 主流程
    // =========================================================

    async function runImagePublish() {
        try {
            // 步骤 1：切换到图文发布模式（点击"发布图文"选项卡）
            window.notifySwift('stepDone', { step: 'switchMode', status: 'start' });
            await switchToImageMode(stepTimeout);
            window.notifySwift('stepDone', { step: 'switchMode', status: 'done' });

            await window.sleep(1000 + Math.random() * 500);

            // 步骤 2：等待图片上传区域就绪
            window.notifySwift('stepDone', { step: 'waitUploadArea', status: 'start' });
            await waitForImageInput(stepTimeout);
            window.notifySwift('stepDone', { step: 'waitUploadArea', status: 'done' });

            // 步骤 3：触发文件选择（Swift 的 WKUIDelegate 拦截并返回图片文件）
            window.notifySwift('stepDone', { step: 'triggerFileInput', status: 'start' });
            var fileInput = document.querySelector(SEL.fileInput)
                || document.querySelector(SEL.fileInputFallback);
            if (!fileInput) {
                throw new Error('未找到图片上传 input 元素');
            }
            fileInput.click();
            window.notifySwift('stepDone', { step: 'triggerFileInput', status: 'done' });

            // 步骤 4：等待图片上传完成
            window.notifySwift('stepDone', { step: 'waitUploadComplete', status: 'start' });
            await waitForImagesUpload(imageCount, params.uploadTimeout || 120000);
            window.notifySwift('stepDone', { step: 'waitUploadComplete', status: 'done' });

            await window.sleep(800 + Math.random() * 400);

            // 步骤 5：填写标题（如有）
            if (title) {
                window.notifySwift('stepDone', { step: 'fillTitle', status: 'start' });
                await fillTitle(title);
                window.notifySwift('stepDone', { step: 'fillTitle', status: 'done' });
                await window.sleep(300 + Math.random() * 300);
            }

            // 步骤 6：填写文案
            window.notifySwift('stepDone', { step: 'fillContent', status: 'start' });
            await fillDescription(content);
            window.notifySwift('stepDone', { step: 'fillContent', status: 'done' });

            await window.sleep(500 + Math.random() * 500);

            // 步骤 7：音乐选择（如有）
            if (hasMusic && musicName && typeof window.selectMusic === 'function') {
                window.notifySwift('stepDone', { step: 'selectMusic', status: 'start' });
                var musicResult = await window.selectMusic(musicName, isVideo);
                if (musicResult.success) {
                    window.notifySwift('stepDone', { step: 'selectMusic', status: 'done' });
                } else {
                    window.notifySwift('stepDone', {
                        step: 'selectMusic',
                        status: 'warning',
                        message: musicResult.reason || '音乐选择失败'
                    });
                }
                await window.sleep(500 + Math.random() * 500);
            }

            // 步骤 8：处理定时发布
            if (hasSchedule && scheduleTime) {
                window.notifySwift('stepDone', { step: 'setSchedule', status: 'start' });
                await setScheduledTime(scheduleTime, stepTimeout);
                window.notifySwift('stepDone', { step: 'setSchedule', status: 'done' });
                await window.sleep(500 + Math.random() * 500);
            }

            // 步骤 8：点击发布按钮
            window.notifySwift('stepDone', { step: 'clickPublish', status: 'start' });
            await clickPublishButton(stepTimeout);
            window.notifySwift('stepDone', { step: 'clickPublish', status: 'done' });

            // 步骤 9：等待发布结果
            window.notifySwift('stepDone', { step: 'watchResult', status: 'start' });
            window.watchPublishResult(params.resultTimeout || 60000);

        } catch (err) {
            window.notifySwift('error', {
                step: 'imagePublish',
                message: err.message || String(err)
            });
        }
    }

    // =========================================================
    // 切换到图文发布模式
    // =========================================================

    async function switchToImageMode(timeout) {
        // 寻找"发布图文"文字的可点击元素
        var candidates = document.querySelectorAll('div, span, button, a, li');
        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (el.children.length === 0 &&
                el.textContent.trim() === SEL.modeSwitchText) {
                el.click();
                return;
            }
        }

        // 如果页面还没加载完，等待后重试
        await window.sleep(2000);
        candidates = document.querySelectorAll('div, span, button, a, li');
        for (var j = 0; j < candidates.length; j++) {
            var el2 = candidates[j];
            if (el2.textContent.trim().indexOf(SEL.modeSwitchText) !== -1 &&
                el2.children.length < 3) {
                el2.click();
                return;
            }
        }

        // 最后尝试通用 clickByText
        var clicked = window.clickByText(SEL.modeSwitchText, 'div');
        if (!clicked) {
            clicked = window.clickByText(SEL.modeSwitchText, 'span');
        }
        // 即使没找到也继续（有些账号默认就是图文模式）
    }

    // =========================================================
    // 等待图片上传 input 就绪
    // =========================================================

    async function waitForImageInput(timeout) {
        // 优先找 accept*='image' 的 input
        try {
            await window.waitForElement(SEL.fileInput, timeout / 2);
            return;
        } catch (e) {
            // 退而使用通用 input
            await window.waitForElement(SEL.fileInputFallback, timeout);
        }
    }

    // =========================================================
    // 等待所有图片上传完成
    // =========================================================

    function waitForImagesUpload(count, timeout) {
        return new Promise(function(resolve, reject) {
            var deadline = Date.now() + timeout;

            var checkInterval = setInterval(function() {
                var bodyText = document.body ? document.body.innerText : '';

                // 检查上传失败
                if (bodyText.indexOf('上传失败') !== -1 ||
                    bodyText.indexOf('格式不支持') !== -1) {
                    clearInterval(checkInterval);
                    reject(new Error('图片上传失败'));
                    return;
                }

                // 检查上传进度是否消失（进度条消失 + 图片缩略图出现 = 上传完成）
                var uploadItems = document.querySelectorAll(
                    "[class*='upload-item'], [class*='image-item'], [class*='img-item']"
                );

                // 检查是否还有上传中的状态
                var isUploading = false;
                var progressEls = document.querySelectorAll(
                    "[class*='progress'], [class*='loading']"
                );
                for (var i = 0; i < progressEls.length; i++) {
                    if (progressEls[i].offsetWidth > 0 || progressEls[i].offsetHeight > 0) {
                        isUploading = true;
                        break;
                    }
                }

                if (!isUploading && uploadItems.length >= count) {
                    clearInterval(checkInterval);
                    resolve();
                    return;
                }

                // 也检测"重新上传"按钮出现（部分版本的上传完成标志）
                if (bodyText.indexOf('重新上传') !== -1 || bodyText.indexOf('添加图片') !== -1) {
                    clearInterval(checkInterval);
                    resolve();
                    return;
                }

                if (Date.now() > deadline) {
                    clearInterval(checkInterval);
                    reject(new Error('等待图片上传完成超时'));
                }
            }, 1500);
        });
    }

    // =========================================================
    // 填写标题
    // =========================================================

    async function fillTitle(titleText) {
        var titleInput = document.querySelector(SEL.titleInput);
        if (!titleInput) {
            // 尝试等待一次
            try {
                titleInput = await window.waitForElement(SEL.titleInput, 5000);
            } catch (e) {
                return; // 没有标题输入框，跳过
            }
        }

        titleInput.focus();
        await window.sleep(200);
        window.setReactInputValue(titleInput, titleText);
        await window.sleep(300);
    }

    // =========================================================
    // 填写发布文案
    // =========================================================

    async function fillDescription(text) {
        if (!text) return;

        var editor = await window.waitForElement(SEL.descEditor, 15000);
        editor.focus();
        await window.sleep(300);

        window.setContentEditableValue(editor, text);
        await window.sleep(500);
    }

    // =========================================================
    // 设置定时发布
    // =========================================================

    async function setScheduledTime(timeStr, timeout) {
        var radioClicked = false;

        // 查找"定时发布"相关的单选/选项
        var radios = document.querySelectorAll("[class^='radio'], [role='radio']");
        for (var i = 0; i < radios.length; i++) {
            if (radios[i].textContent.indexOf('定时发布') !== -1) {
                radios[i].click();
                radioClicked = true;
                break;
            }
        }

        if (!radioClicked) {
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

        var timeInput = await window.waitForElement(SEL.scheduleInput, timeout);
        timeInput.focus();
        await window.sleep(300);

        window.setReactInputValue(timeInput, timeStr);
        timeInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

        await window.sleep(500);
    }

    // =========================================================
    // 点击发布按钮
    // =========================================================

    async function clickPublishButton(timeout) {
        var clicked = window.clickByText('发布', 'button');
        if (clicked) return;

        var btn = await window.waitForElement(SEL.publishBtn, timeout);
        btn.click();
    }

    // =========================================================
    // 启动
    // =========================================================

    runImagePublish();

})();
