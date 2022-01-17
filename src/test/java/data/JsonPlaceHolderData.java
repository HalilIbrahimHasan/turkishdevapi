package data;

import java.util.HashMap;
import java.util.Map;

public class JsonPlaceHolderData {

    /*
       When
             I send POST Request to the Url https://jsonplaceholder.typicode.com/todos
             with the request body {
                                   "userId": 55,
                                   "title": "Tidy your room",
                                   "completed": false
                                  }
       Then
           Status code is 201
           And response body is like {
                                       "userId": 55,
                                       "title": "Tidy your room",
                                       "completed": false,
                                       "id": 201
                                     }
    */
    public static Map<String, Object> expectedDataSetup(){

        Map<String, Object> expectedData = new HashMap<>();

        expectedData.put("userId", 55);
        expectedData.put("title", "Tidy your room");
        expectedData.put("completed", false);


        return expectedData;

    }


    public static Map<String, Object> expectedDataPut(){


        Map<String, Object> expectedData = new HashMap<>();
        expectedData.put("userId", 21);
        expectedData.put("title", "bulasiklari yikayiniz");
        expectedData.put("completed", false);

        return expectedData;


    }


}
