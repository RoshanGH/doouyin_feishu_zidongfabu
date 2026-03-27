/**
 * douyin_helpers.js
 * 抖音自动化发布通用工具函数库
 * 注入时机：document_end，所有页面帧
 */

(function() {
    'use strict';

    // =========================================================
    // waitForElement — 用 MutationObserver 等待元素出现
    // =========================================================

    /**
     * 等待指定 CSS 选择器的元素出现在 DOM 中
     * @param {string} selector  CSS 选择器
     * @param {number} timeout   超时毫秒数（默认 30000）
     * @returns {Promise<Element>} 找到的元素
     */
    window.waitForElement = function(selector, timeout) {
        timeout = timeout || 30000;
        return new Promise(function(resolve, reject) {
            var deadline = Date.now() + timeout;

            // 先检查元素是否已经存在
            var existing = document.querySelector(selector);
            if (existing) {
                resolve(existing);
                return;
            }

            var observer = new MutationObserver(function() {
                var el = document.querySelector(selector);
                if (el) {
                    observer.disconnect();
                    resolve(el);
                } else if (Date.now() > deadline) {
                    observer.disconnect();
                    reject(new Error('waitForElement timeout: ' + selector));
                }
            });

            observer.observe(document.body || document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                characterData: false
            });

            // 兜底超时
            setTimeout(function() {
                observer.disconnect();
                var el = document.querySelector(selector);
                if (el) {
                    resolve(el);
                } else {
                    reject(new Error('waitForElement timeout: ' + selector));
                }
            }, timeout);
        });
    };

    // =========================================================
    // setReactInputValue — React 兼容的输入值设置
    // =========================================================

    /**
     * 以 React 感知的方式修改 input/textarea 的值
     * React 内部用 Object.defineProperty 覆盖了 value 的 setter，
     * 直接赋值不会触发 onChange，需要模拟原生 setter。
     * @param {HTMLElement} element  目标输入元素
     * @param {string}      value    要设置的值
     */
    window.setReactInputValue = function(element, value) {
        var nativeInputValueSetter = null;

        if (element.tagName === 'INPUT') {
            nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value'
            );
        } else if (element.tagName === 'TEXTAREA') {
            nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            );
        }

        if (nativeInputValueSetter && nativeInputValueSetter.set) {
            nativeInputValueSetter.set.call(element, value);
        } else {
            element.value = value;
        }

        // 依次触发 React 监听的事件链
        var inputEvent = new Event('input', { bubbles: true, cancelable: true });
        element.dispatchEvent(inputEvent);

        var changeEvent = new Event('change', { bubbles: true, cancelable: true });
        element.dispatchEvent(changeEvent);
    };

    // =========================================================
    // setContentEditable — 针对 contenteditable 元素的文本插入
    // =========================================================

    /**
     * 向 contenteditable 元素插入文本（兼容抖音富文本编辑器）
     * @param {HTMLElement} element  contenteditable 元素
     * @param {string}      text     要插入的文本
     */
    window.setContentEditableValue = function(element, text) {
        element.focus();

        // 全选已有内容
        document.execCommand('selectAll', false, null);
        // 删除选中内容
        document.execCommand('delete', false, null);
        // 插入新文本
        document.execCommand('insertText', false, text);

        // 触发 input 事件确保 React/Vue 感知到变化
        var inputEvent = new InputEvent('input', {
            bubbles: true,
            cancelable: true,
            inputType: 'insertText',
            data: text
        });
        element.dispatchEvent(inputEvent);
    };

    // =========================================================
    // watchPublishResult — 监听发布结果
    // =========================================================

    /**
     * 监听发布结果：检测 URL 变化或 DOM 出现"发布成功"字样
     * 结果通过 notifySwift("publishResult", {...}) 回调
     * @param {number} timeout  超时毫秒数（默认 120000）
     */
    window.watchPublishResult = function(timeout) {
        timeout = timeout || 120000;
        var startTime = Date.now();
        var originalHref = location.href;
        var resolved = false;

        function finish(success, message) {
            if (resolved) return;
            resolved = true;
            window.notifySwift('publishResult', {
                success: success,
                message: message || '',
                url: location.href
            });
        }

        // 检测成功文字的 DOM 观察器
        var successKeywords = ['发布成功', '已发布', '内容已提交'];
        var failKeywords = ['发布失败', '上传失败', '提交失败'];

        var observer = new MutationObserver(function() {
            var bodyText = document.body ? document.body.innerText : '';

            for (var i = 0; i < successKeywords.length; i++) {
                if (bodyText.indexOf(successKeywords[i]) !== -1) {
                    observer.disconnect();
                    finish(true, successKeywords[i]);
                    return;
                }
            }

            for (var j = 0; j < failKeywords.length; j++) {
                if (bodyText.indexOf(failKeywords[j]) !== -1) {
                    observer.disconnect();
                    finish(false, failKeywords[j]);
                    return;
                }
            }

            // URL 变化（跳转到发布成功页）
            if (location.href !== originalHref &&
                (location.href.indexOf('success') !== -1 ||
                 location.href.indexOf('manage') !== -1)) {
                observer.disconnect();
                finish(true, 'URL 跳转到: ' + location.href);
                return;
            }
        });

        if (document.body) {
            observer.observe(document.body, {
                childList: true,
                subtree: true,
                characterData: true
            });
        }

        // 超时兜底
        setTimeout(function() {
            if (!resolved) {
                observer.disconnect();
                finish(false, '等待发布结果超时（' + timeout + 'ms）');
            }
        }, timeout);
    };

    // =========================================================
    // notifySwift — 向 Swift 发送消息
    // =========================================================

    /**
     * 通过 WKScriptMessageHandler 向 Swift 层发送消息
     * @param {string} name  消息处理器名称（如 "stepDone", "error", "publishResult"）
     * @param {*}      data  要传递的数据（会被序列化为 JSON）
     */
    window.notifySwift = function(name, data) {
        try {
            if (window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers[name]) {
                window.webkit.messageHandlers[name].postMessage(data);
            }
        } catch (e) {
            // 在非 WKWebView 环境下静默忽略
        }
    };

    // =========================================================
    // sleep — Promise 版延迟
    // =========================================================

    /**
     * 等待指定毫秒
     * @param {number} ms 毫秒数
     * @returns {Promise<void>}
     */
    window.sleep = function(ms) {
        return new Promise(function(resolve) { setTimeout(resolve, ms); });
    };

    // =========================================================
    // clickElement — 安全点击
    // =========================================================

    /**
     * 安全地点击指定选择器对应的元素
     * @param {string} selector CSS 选择器
     * @returns {boolean} 是否成功点击
     */
    window.clickElement = function(selector) {
        var el = document.querySelector(selector);
        if (el) {
            el.click();
            return true;
        }
        return false;
    };

    /**
     * 通过文本内容查找并点击按钮或链接
     * @param {string} text  按钮文本
     * @param {string} tag   HTML 标签名（默认 'button'）
     * @returns {boolean} 是否成功点击
     */
    window.clickByText = function(text, tag) {
        tag = tag || 'button';
        var elements = document.querySelectorAll(tag);
        for (var i = 0; i < elements.length; i++) {
            if (elements[i].textContent.trim().indexOf(text) !== -1) {
                elements[i].click();
                return true;
            }
        }
        return false;
    };

})();
