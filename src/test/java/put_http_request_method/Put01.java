package put_http_request_method;

import base_urls.JsonPlaceHolderBaseUrl;
import io.restassured.http.ContentType;
import io.restassured.path.json.JsonPath;
import io.restassured.response.Response;
import org.junit.Test;
import pojos.Todo;

import java.util.HashMap;
import java.util.Map;

import static data.JsonPlaceHolderData.expectedDataPut;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.Assert.assertEquals;

public class Put01 extends JsonPlaceHolderBaseUrl {



       /*
         When
	 		I send PUT Request to the Url https://jsonplaceholder.typicode.com/todos/198
	 		with the PUT Request body like {
										    "userId": 21,
										    "title": "bulasiklari yikayiniz",
										    "completed": false
										   }
	     Then
	   	   Status code is 200
	   	   And response body is like   {
									    "userId": 21,
									    "title": "bulasiklari yikayiniz",
									    "completed": false,
									    "
									   }
     */


    @Test
    public void put01(){


        //set the url
        spec.pathParams("bir" , "todos", "iki", 198);


        //Set the expected data
        Map<String, Object> expectedData = expectedDataPut();


        //Send the Put request and get the response / Put request yollayin ve Response elde edin
        Response response = given().spec(spec).contentType(ContentType.JSON).body(expectedData).when().put("/{bir}/{iki}");

        response.prettyPrint();


        //validate
        //1. yol
        response.then().assertThat().statusCode(200).
                body("userId", equalTo(21)).
                body("title",equalTo("bulasiklari yikayiniz") ).
                body("completed",equalTo(false));


        //2. yol
        Map<String, Object> actualData = response.as(HashMap.class);

        assertEquals(expectedData.get("userId"), actualData.get("userId"));
        assertEquals(expectedData.get("title"), actualData.get("title"));
        assertEquals(expectedData.get("completed"), actualData.get("completed"));



        //3. yol

        Todo actualTodo = response.as(Todo.class);


        assertEquals(expectedData.get("userId"), actualTodo.getUserId());
        assertEquals(expectedData.get("title"), actualTodo.getTitle());
        assertEquals(expectedData.get("completed"), actualTodo.isCompleted());


        //4. yol
        JsonPath json = response.jsonPath();
        assertEquals(expectedData.get("userId"), json.getInt("userId"));
        assertEquals(expectedData.get("title"), json.getString("title"));
        assertEquals(expectedData.get("completed"), json.getBoolean("completed"));


    }

}
