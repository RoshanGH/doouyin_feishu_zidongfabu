/**
 * douyin_music_select.js
 * 抖音音乐搜索与选择脚本（视频/图文发布通用）
 *
 * 依赖：douyin_helpers.js 中的 waitForElement、setReactInputValue
 *
 * 流程：
 *   1. 点击"添加音乐"/"选择音乐"入口按钮
 *   2. 等待音乐面板加载
 *   3. 在搜索框输入音乐名称（React 受控组件）
 *   4. 等待搜索结果
 *   5. 点击第一个"使用"按钮
 *   6. 等待音乐应用完成
 *
 * 调用方式（由 Swift 端 evaluateJavaScript 触发）：
 *   window.selectMusic("草莓不能 创作的原声", true)
 *     .then(r => window.webkit.messageHandlers.musicResult.postMessage(r))
 *     .catch(e => window.webkit.messageHandlers.musicResult.postMessage({
 *       success: false, reason: e.message
 *     }));
 */

(function() {
    'use strict';

    /**
     * 通过文字内容查找可点击元素
     * @param {string} text  目标文字
     * @returns {HTMLElement|null}
     */
    function findElementByText(text) {
        var candidates = document.querySelectorAll('span, div, button, a');
        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (el.textContent.trim() === text && el.offsetParent !== null) {
                return el;
            }
        }
        return null;
    }

    /**
     * 等待指定毫秒
     * @param {number} ms
     * @returns {Promise<void>}
     */
    function sleep(ms) {
        return new Promise(function(resolve) {
            setTimeout(resolve, ms);
        });
    }

    /**
     * 搜索并选择音乐
     * @param {string}  musicName  音乐名称
     * @param {boolean} isVideo    是否为视频发布（决定入口按钮文字）
     * @returns {Promise<{success: boolean, reason?: string}>}
     */
    window.selectMusic = function(musicName, isVideo) {
        var SEARCH_TIMEOUT = 5000;
        var USE_BUTTON_WAIT = 3000;

        return (async function() {
            // 1. 点击入口按钮
            var buttonText = isVideo ? '添加音乐' : '选择音乐';
            var entryButton = findElementByText(buttonText);

            if (!entryButton) {
                return { success: false, reason: '未找到音乐入口按钮「' + buttonText + '」' };
            }

            entryButton.click();
            await sleep(1000);

            // 2. 等待搜索框出现
            var searchInput;
            try {
                searchInput = await window.waitForElement(
                    'input[placeholder="搜索音乐"]',
                    5000
                );
            } catch (e) {
                return { success: false, reason: '音乐面板加载超时' };
            }

            // 3. 在搜索框输入音乐名称
            searchInput.focus();
            await sleep(300);
            window.setReactInputValue(searchInput, musicName);
            await sleep(300);

            // 模拟 Enter 键触发搜索
            searchInput.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13,
                bubbles: true
            }));

            // 4. 等待搜索结果（"使用"按钮出现）
            var useButton;
            try {
                useButton = await window.waitForElement(
                    'button[class*="apply-btn-"]',
                    SEARCH_TIMEOUT
                );
            } catch (e) {
                return { success: false, reason: '未找到音乐：' + musicName };
            }

            // 确保按钮可见且可交互
            await sleep(500);

            // 5. 点击第一个"使用"按钮
            var allUseButtons = document.querySelectorAll('button[class*="apply-btn-"]');
            if (allUseButtons.length === 0) {
                return { success: false, reason: '使用按钮未找到' };
            }

            allUseButtons[0].click();

            // 6. 等待音乐应用完成
            await sleep(USE_BUTTON_WAIT);

            return { success: true, musicName: musicName };
        })();
    };

})();
