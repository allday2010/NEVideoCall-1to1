package com.netease.yunxin.app.videocall.nertc.biz;


import com.netease.yunxin.app.videocall.base.BaseService;
import com.netease.yunxin.kit.alog.ALog;
import com.netease.yunxin.app.videocall.login.model.UserModel;

import org.json.JSONException;
import org.json.JSONObject;

import okhttp3.MediaType;
import okhttp3.RequestBody;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;
import retrofit2.http.Body;
import retrofit2.http.POST;

public class CallServiceManager {

    private static final String LOG_TAG = "CallServiceManager";

    private final CallApi mApi;

    private Call<BaseService.ResponseEntity<UserModel>> searchUserCall;

    private CallServiceManager() {
        mApi = BaseService.getInstance().getRetrofit().create(CallApi.class);
    }

    public static CallServiceManager getInstance() {
        return new CallServiceManager();
    }


    /**
     * 网络访问接口
     */
    private interface CallApi {
        @POST("/p2pVideoCall/caller/searchSubscriber")
        Call<BaseService.ResponseEntity<UserModel>> searchUserWithPhoneNumber(@Body RequestBody body);
    }

    /**
     * 根据手机号码精确搜索用户
     */
    public void searchUserWithPhoneNumber(String phoneNumber, final BaseService.ResponseCallBack<UserModel> callBack) {
        if (searchUserCall != null && searchUserCall.isExecuted()) {
            ALog.e(LOG_TAG, "searchUserCall is executed");
            searchUserCall.cancel();
        }
        JSONObject result = new JSONObject();
        try {
            result.put("mobile", phoneNumber);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        RequestBody body = RequestBody.create(MediaType.parse("application/json"), result.toString());
        searchUserCall = mApi.searchUserWithPhoneNumber(body);
        searchUserCall.enqueue(new Callback<BaseService.ResponseEntity<UserModel>>() {
            @Override
            public void onResponse(Call<BaseService.ResponseEntity<UserModel>> call, Response<BaseService.ResponseEntity<UserModel>> response) {
                if (callBack != null) {
                    BaseService.ResponseEntity<UserModel> responseEntity = response.body();
                    if (responseEntity.code == 200) {
                        callBack.onSuccess(responseEntity.data);
                    } else {
                        callBack.onFail(responseEntity.code);
                    }
                }
            }

            @Override
            public void onFailure(Call<BaseService.ResponseEntity<UserModel>> call, Throwable t) {
                if (callBack != null) {
                    callBack.onFail(BaseService.ERROR_CODE_UNKNOWN);
                }
            }
        });

    }

}
