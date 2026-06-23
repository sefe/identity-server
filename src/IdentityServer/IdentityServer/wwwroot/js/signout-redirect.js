// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

window.addEventListener("load", function () {
    var a = document.querySelector("a.PostLogoutRedirectUri");
    if (a) {
        window.location = a.href;
    }
});
