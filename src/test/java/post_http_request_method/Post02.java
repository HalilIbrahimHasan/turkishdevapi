package post_http_request_method;

import base_urls.JsonPlaceHolderBaseUrl;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import org.junit.Test;
import pojos.Todo;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertEquals;

public class Post02 extends JsonPlaceHolderBaseUrl {

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

    @Test
    public void post02(){

        //Set the url
        spec.pathParams("bir", "todos");


        //Set the expected data
        Todo expectedTodo = new Todo(55,"Tidy your room",  false );


        //Send the Post Request and Get the response / Post request yap ve Response elde et
        Response response = given().spec(spec).contentType(ContentType.JSON).body(expectedTodo).when().post("/{bir}");

        response.prettyPrint();
        expectedTodo.setId(201);

        Todo actualTodo = response.as(Todo.class);

        //Validate
        assertEquals(expectedTodo.getUserId(), actualTodo.getUserId());
        assertEquals(expectedTodo.getTitle(), actualTodo.getTitle());
        assertEquals(expectedTodo.isCompleted(), actualTodo.isCompleted());
        assertEquals(expectedTodo.getId(), actualTodo.getId());


    }



}
