package post_http_request_method;

import base_urls.JsonPlaceHolderBaseUrl;
import data.JsonPlaceHolderData;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import org.junit.Test;

import java.util.Map;

import static data.JsonPlaceHolderData.expectedDataSetup;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

public class Post03 extends JsonPlaceHolderBaseUrl {

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
                                     auth: admin
                                     sifre: 1234
    */

    @Test
    public void post03(){

        //Set the base url
        spec.pathParams("bir", "todos");

        //Set the expected data
        Map<String,Object> expectedData = expectedDataSetup();

        //Send the Post requend and Get response / Post request yap ve response elde et

        Response response = given().spec(spec).auth().basic("admin", "1234").
                contentType(ContentType.JSON).
                body(expectedData).when().post("/{bir}");

        response.prettyPrint();


        //validate
        response.then().assertThat().statusCode(201).body("userId", equalTo(55),
                "title", equalTo("Tidy your room"), "completed", equalTo(false));

    }




}
