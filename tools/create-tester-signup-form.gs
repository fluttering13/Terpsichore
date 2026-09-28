/**
 * Paste into https://script.google.com/home/start and run createTesterSignupForm.
 * Creates one Google Form in the executing user's account. Does not send email.
 * Re-running this script reuses its form and preserves existing responses.
 */
function createTesterSignupForm() {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const properties = PropertiesService.getScriptProperties();
    const existingId = properties.getProperty('TERPSICHORE_SIGNUP_FORM_ID');
    if (existingId) {
      const existing = FormApp.openById(existingId);
      console.log('填寫連結：' + existing.getPublishedUrl());
      console.log('管理與查看回覆：' + existing.getEditUrl());
      return;
    }

    const form = FormApp.create('Terpsichore 舞蹈練習 App 封測報名', false);
    form.setDescription(
      '歡迎參加 Android 封閉測試！請留下 Google Play 使用的帳號信箱，我會寄送測試邀請。\n\n' +
      '加入後請保持參與至少 14 天，期間有空試用並分享建議。信箱僅用於本次測試聯絡，不會公開。'
    );
    form.setCollectEmail(false);
    form.setLimitOneResponsePerUser(false);
    form.setPublishingSummary(false);
    form.setShowLinkToRespondAgain(false);
    form.setConfirmationMessage(
      '報名成功！請留意 Email，收到邀請後再依連結加入測試並下載 App。'
    );
    form.addTextItem()
      .setTitle('Google Play 帳號信箱')
      .setRequired(true)
      .setValidation(FormApp.createTextValidation()
        .requireTextIsEmail()
        .setHelpText('請輸入完整的電子郵件地址，例如 name@gmail.com')
        .build());
    form.setPublished(true);
    form.setAcceptingResponses(true);
    properties.setProperty('TERPSICHORE_SIGNUP_FORM_ID', form.getId());
    console.log('填寫連結：' + form.getPublishedUrl());
    console.log('管理與查看回覆：' + form.getEditUrl());
  } finally {
    lock.releaseLock();
  }
}
