package get_http_request_method;

import base_urls.JsonPlaceHolderBaseUrl;
import io.restassured.response.Response;
import org.junit.Test;
import pojos.Todo;

import java.util.HashMap;
import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertEquals;

public class Get08 extends JsonPlaceHolderBaseUrl {




     /*
     Given
            https://jsonplaceholder.typicode.com/todos/2
     When I send a Get Request

     Then the actual data should be as following;
        {
        "userId": 1,
        "id": 2,
        "title": "quis ut nam facilis et officia qui",
        "completed": false
    }

     */

    @Test
    public void get08(){

        //Set the url
        spec.pathParams("bir", "todos", "iki",2 );


        //set the expected data / beklenen data yi olusturunuz

        Map<String, Object> expectedData = new HashMap<>();

        expectedData.put("userId", 1);
        expectedData.put("id", 2);
        expectedData.put("title", "quis ut nam facilis et officia qui");
        expectedData.put("completed", false);


        //Send the Get Request and Get the response / Get request yolla ve Response al

        Response response = given().spec(spec).when().get("/{bir}/{iki}");

       //Validate / Control et

        Map<String, Object> actualData = response.as(HashMap.class);


        assertEquals("Beklenen veriler ve karsilasilan veriler farkli", expectedData.get("userId"), actualData.get("userId"));
        assertEquals("Beklenen veriler ve karsilasilan veriler farkli", expectedData.get("id"), actualData.get("id"));
        assertEquals("Beklenen veriler ve karsilasilan veriler farkli", expectedData.get("title"), actualData.get("title"));
        assertEquals("Beklenen veriler ve karsilasilan veriler farkli", expectedData.get("completed"), actualData.get("completed"));





    }


    @Test
    public void testWIthPojo(){

        //Set the url
        spec.pathParams("bir", "todos", "iki",2 );

        //Set the expected data / beklenen datayi olusturunuz
        Todo expectedTodo = new Todo(1, 2,"quis ut nam facilis et officia qui", false );


        //Send the Get request and Get the response / Get Request yolla ve Response elde et
        Response response = given().spec(spec).when().get("/{bir}/{iki}");

        //2. yol validation icin
        Todo actualTodo = response.as(Todo.class);

        assertEquals("Beklenen data karsilasilan ile uyusmadi!",expectedTodo.getUserId(), actualTodo.getUserId() );
        assertEquals("Beklenen data karsilasilan ile uyusmadi!",expectedTodo.getTitle(), actualTodo.getTitle() );
        assertEquals("Beklenen data karsilasilan ile uyusmadi!",expectedTodo.getId(), actualTodo.getId() );
        assertEquals("Beklenen data karsilasilan ile uyusmadi!",expectedTodo.isCompleted(), actualTodo.isCompleted() );


    }

}
